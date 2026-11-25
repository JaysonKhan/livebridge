#include "wasapi_sink.h"

#include <windows.h>

#include <objbase.h>

#include <audioclient.h>
#include <avrt.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstring>

#include "scoped_handle.h"
#include "win_util.h"

namespace {

using Microsoft::WRL::ComPtr;

// One frame: a single 16-bit sample (mono).
const WORD kBytesPerFrame = 2;
// 30 s: a whole long turn fits, and nothing can grow without bound.
const std::size_t kQueueSamples = static_cast<std::size_t>(WasapiSink::kSampleRate) * 30;
// Audio queued before a turn starts playing, which absorbs network jitter: 80 ms.
const std::size_t kPrebufferSamples = static_cast<std::size_t>(WasapiSink::kSampleRate) * 80 / 1000;
// How much the system may hold for us: 100 ms, in units of 100 ns (a REFERENCE_TIME).
const REFERENCE_TIME kBufferDuration = 100 * 10'000;
// How far ahead of the speaker the device is kept fed: 40 ms, less than its whole buffer. That is margin enough for a
// late wake-up, keeps `consumed` close to what is actually heard, and has the queue read in device-period steps, so
// that a primed 80 ms turn is not swallowed (and taken for an underrun) in one gulp.
const UINT32 kTargetFrames = static_cast<UINT32>(WasapiSink::kSampleRate) * 40 / 1000;
// The device signals its event every period (about 10 ms); the time-out keeps the thread going should it not.
const DWORD kWaitMs = 10;

// Opens the endpoint for 48 kHz mono 16-bit playback, primes it with silence and starts it. On failure `step` names
// what was refused.
HRESULT OpenRender(const std::wstring& device_id, HANDLE ready, ComPtr<IAudioClient>& client,
                   ComPtr<IAudioRenderClient>& render, UINT32& buffer_frames, const char*& step) {
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDevice> device;
  step = "the device list";
  HRESULT result = ::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                      IID_PPV_ARGS(enumerator.GetAddressOf()));
  if (FAILED(result)) return result;
  step = "finding the device";
  result = enumerator->GetDevice(device_id.c_str(), device.GetAddressOf());
  if (FAILED(result)) return result;
  step = "activating the device";
  result = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                            reinterpret_cast<void**>(client.GetAddressOf()));
  if (FAILED(result)) return result;

  WAVEFORMATEX wave = {};
  wave.wFormatTag = WAVE_FORMAT_PCM;
  wave.nChannels = 1;
  wave.nSamplesPerSec = static_cast<DWORD>(WasapiSink::kSampleRate);
  wave.wBitsPerSample = 16;
  wave.nBlockAlign = kBytesPerFrame;
  wave.nAvgBytesPerSec = static_cast<DWORD>(WasapiSink::kSampleRate) * kBytesPerFrame;
  wave.cbSize = 0;
  // AUTOCONVERTPCM: the system's mixer resamples and spreads our mono over the device's own format.
  step = "setting up the stream";
  result = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                              AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                                  AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                              kBufferDuration, 0, &wave, nullptr);
  if (FAILED(result)) return result;
  step = "the stream's event";
  result = client->SetEventHandle(ready);
  if (FAILED(result)) return result;
  step = "the buffer size";
  result = client->GetBufferSize(&buffer_frames);
  if (FAILED(result)) return result;
  step = "the playback service";
  result = client->GetService(IID_PPV_ARGS(render.GetAddressOf()));
  if (FAILED(result)) return result;

  // Silence first, so that the device has something to play from its first cycle.
  step = "priming the stream";
  const UINT32 prime = std::min(buffer_frames, kTargetFrames);
  BYTE* buffer = nullptr;
  result = render->GetBuffer(prime, &buffer);
  if (FAILED(result)) return result;
  result = render->ReleaseBuffer(prime, AUDCLNT_BUFFERFLAGS_SILENT);
  if (FAILED(result)) return result;
  step = "starting the stream";
  return client->Start();
}

}  // namespace

WasapiSink::WasapiSink() : ring_(kQueueSamples) {}

WasapiSink::~WasapiSink() { Close(); }

bool WasapiSink::Open(const std::string& device_uid, livebridge::HostError& error) {
  Close();
  stop_.store(false);
  start_done_ = false;
  const std::wstring device_id = Utf16FromUtf8(device_uid);
  thread_ = std::thread([this, device_id] { Run(device_id); });

  long result = 0;
  const char* step = "";
  {
    std::unique_lock<std::mutex> lock(start_mutex_);
    start_answered_.wait(lock, [this] { return start_done_; });
    result = start_result_;
    step = start_step_;
  }
  if (SUCCEEDED(result)) return true;

  thread_.join();
  error.code = "device";
  error.message = std::string("The output device cannot be opened (") + step + ", HRESULT " +
                  HexCode(static_cast<unsigned long>(result)) + ").";
  return false;
}

void WasapiSink::Close() {
  if (thread_.joinable()) {
    stop_.store(true);
    thread_.join();
  }
}

bool WasapiSink::Write(const std::uint8_t* pcm, std::size_t bytes, int sample_rate) {
  const std::size_t samples = bytes / sizeof(std::int16_t);
  if (samples == 0) return true;
  if (sample_rate <= 0) return false;
  auto found = resamplers_.find(sample_rate);
  if (found == resamplers_.end()) found = resamplers_.try_emplace(sample_rate, sample_rate, kSampleRate).first;
  // Copied, so that the samples are aligned whatever the caller's buffer is.
  pcm_.resize(samples);
  std::memcpy(pcm_.data(), pcm, samples * sizeof(std::int16_t));
  converted_.clear();
  found->second.process(pcm_.data(), samples, converted_);
  // Before the samples land: the render thread must not see them together with the previous turn's "ended" and
  // start this turn without its prebuffer.
  input_ended_.store(false);
  return ring_.write(converted_.data(), converted_.size()) == converted_.size();
}

void WasapiSink::EndInput() {
  for (auto& entry : resamplers_) {
    converted_.clear();
    entry.second.finish(converted_);
    // A tail that does not fit is lost like any overflow; the turn's own write has reported that already.
    ring_.write(converted_.data(), converted_.size());
  }
  input_ended_.store(true);
}

void WasapiSink::Flush() {
  // "Ended" first: the render thread then reads the queue run dry as the end it is, not as an underrun.
  input_ended_.store(true);
  ring_.flush();
  for (auto& entry : resamplers_) entry.second.reset();
}

double WasapiSink::queued_ms() const {
  return static_cast<double>(ring_.available_to_read()) * 1000.0 / kSampleRate;
}

void WasapiSink::Run(const std::wstring& device_id) {
  const HRESULT com = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    // In this scope, so that the device is released before COM is; the event goes last, after the stream that
    // signals it.
    ScopedHandle ready(::CreateEventW(nullptr, FALSE, FALSE, nullptr));
    ComPtr<IAudioClient> client;
    ComPtr<IAudioRenderClient> render;
    UINT32 buffer_frames = 0;
    const char* step = "COM";
    HRESULT result = com;
    // (Should the event be missing, SetEventHandle refuses it and that step is reported.)
    if (SUCCEEDED(result)) result = OpenRender(device_id, ready.get(), client, render, buffer_frames, step);
    {
      std::lock_guard<std::mutex> lock(start_mutex_);
      start_result_ = result;
      start_step_ = step;
      start_done_ = true;
    }
    start_answered_.notify_one();

    if (SUCCEEDED(result)) {
      // Audio priority for this thread, where the system offers it; playback works without.
      DWORD task_index = 0;
      const HANDLE priority = ::AvSetMmThreadCharacteristicsW(L"Pro Audio", &task_index);
      Play(client.Get(), render.Get(), ready.get(), buffer_frames);
      if (priority != nullptr) ::AvRevertMmThreadCharacteristics(priority);
      // Nothing to do about a failure here: the stream is released right below.
      client->Stop();
    }
  }
  if (SUCCEEDED(com)) ::CoUninitialize();
}

void WasapiSink::Play(IAudioClient* client, IAudioRenderClient* render, void* ready, std::uint32_t buffer_frames) {
  const UINT32 target = std::min(buffer_frames, kTargetFrames);
  // Allocated once, here: nothing below allocates.
  std::vector<float> scratch(target);
  bool gate_open = false;
  while (!stop_.load()) {
    if (::WaitForSingleObject(ready, kWaitMs) == WAIT_FAILED) break;
    UINT32 padding = 0;
    // A failure means the device was unplugged or reconfigured; the engine hears about that from the device list.
    if (FAILED(client->GetCurrentPadding(&padding))) break;
    if (padding >= target) continue;
    const UINT32 wanted = target - padding;
    BYTE* buffer = nullptr;
    if (FAILED(render->GetBuffer(wanted, &buffer))) break;

    std::size_t got = 0;
    if (!gate_open) {
      // Start once the jitter buffer is primed, or at once when the whole (short) turn is here.
      const std::size_t available = ring_.available_to_read();
      gate_open = available >= kPrebufferSamples || (available > 0 && input_ended_.load());
    }
    if (gate_open) {
      got = ring_.read(scratch.data(), wanted);
      if (got < wanted) {
        gate_open = false;
        if (!input_ended_.load()) underruns_.fetch_add(1);
      }
    }

    DWORD release = 0;
    if (got == 0 || muted_.load()) {
      // Muted audio was still taken from the queue above: it is discarded in real time, not saved for later.
      release = AUDCLNT_BUFFERFLAGS_SILENT;
    } else {
      std::int16_t* samples = reinterpret_cast<std::int16_t*>(buffer);
      // Rounds and clamps, so resampler overshoot saturates instead of wrapping.
      livebridge::float_to_int16(scratch.data(), got, samples);
      std::fill(samples + got, samples + wanted, std::int16_t{0});
    }
    if (FAILED(render->ReleaseBuffer(wanted, release))) break;
  }
}
