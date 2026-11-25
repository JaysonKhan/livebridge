#include "wasapi_capture.h"

#include <windows.h>

#include <objbase.h>

#include <audioclient.h>
#include <avrt.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <utility>
#include <vector>

#include "win_util.h"

namespace {

using Microsoft::WRL::ComPtr;

const DWORD kSampleRate = 16'000;
// One frame: a single 16-bit sample (mono).
const WORD kBytesPerFrame = 2;
// How much audio the system holds for us between polls: 200 ms, in units of 100 ns (a REFERENCE_TIME).
const LONGLONG kBufferDuration = 200 * 10'000;
const DWORD kPollMs = 10;
const double kSilenceDb = -120.0;

// Opens the endpoint for 16 kHz mono 16-bit capture and starts it. On failure `step` names what was refused.
HRESULT Open(const std::wstring& device_id, ComPtr<IAudioClient>& client, ComPtr<IAudioCaptureClient>& capture,
             const char*& step) {
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

  WAVEFORMATEX format = {};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 1;
  format.nSamplesPerSec = kSampleRate;
  format.wBitsPerSample = 16;
  format.nBlockAlign = kBytesPerFrame;
  format.nAvgBytesPerSec = kSampleRate * kBytesPerFrame;
  format.cbSize = 0;
  // AUTOCONVERTPCM: the system's mixer resamples and down-mixes from the device's own format to ours.
  step = "setting up the stream";
  result = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                              AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                              kBufferDuration, 0, &format, nullptr);
  if (FAILED(result)) return result;
  step = "the capture service";
  result = client->GetService(IID_PPV_ARGS(capture.GetAddressOf()));
  if (FAILED(result)) return result;
  step = "starting the stream";
  return client->Start();
}

// The loudest sample of a block of PCM s16le, in dBFS.
double PeakDb(const std::vector<std::uint8_t>& pcm) {
  int peak = 0;
  for (std::size_t at = 0; at + 1 < pcm.size(); at += 2) {
    const int sample = static_cast<std::int16_t>(static_cast<std::uint16_t>(pcm[at] | (pcm[at + 1] << 8)));
    peak = std::max(peak, std::abs(sample));
  }
  return peak == 0 ? kSilenceDb : std::max(kSilenceDb, 20.0 * std::log10(peak / 32768.0));
}

}  // namespace

WasapiCapture::~WasapiCapture() { Stop(); }

bool WasapiCapture::Start(const std::string& device_uid, AudioCallback on_audio, livebridge::HostError& error) {
  Stop();
  on_audio_ = std::move(on_audio);
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
  on_audio_ = nullptr;
  error.code = "no_microphone";
  error.message = std::string("The microphone cannot be opened (") + step + ", HRESULT " +
                  HexCode(static_cast<unsigned long>(result)) + ").";
  return false;
}

void WasapiCapture::Stop() {
  if (thread_.joinable()) {
    stop_.store(true);
    thread_.join();
  }
  on_audio_ = nullptr;
}

void WasapiCapture::Run(const std::wstring& device_id) {
  const HRESULT com = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    // In this scope, so that the device is released before COM is.
    ComPtr<IAudioClient> client;
    ComPtr<IAudioCaptureClient> capture;
    const char* step = "COM";
    HRESULT result = com;
    if (SUCCEEDED(result)) result = Open(device_id, client, capture, step);
    {
      std::lock_guard<std::mutex> lock(start_mutex_);
      start_result_ = result;
      start_step_ = step;
      start_done_ = true;
    }
    start_answered_.notify_one();

    if (SUCCEEDED(result)) {
      // Audio priority for this thread, where the system offers it; capture works without.
      DWORD task_index = 0;
      const HANDLE priority = ::AvSetMmThreadCharacteristicsW(L"Pro Audio", &task_index);
      Poll(capture.Get());
      if (priority != nullptr) ::AvRevertMmThreadCharacteristics(priority);
      // Nothing to do about a failure here: the stream is released right below.
      client->Stop();
    }
  }
  if (SUCCEEDED(com)) ::CoUninitialize();
}

void WasapiCapture::Poll(IAudioCaptureClient* capture) {
  std::vector<std::uint8_t> block;
  bool running = true;
  while (running && !stop_.load()) {
    ::Sleep(kPollMs);
    // Take every packet that has arrived since the last poll.
    for (;;) {
      UINT32 frames = 0;
      BYTE* data = nullptr;
      DWORD flags = 0;
      if (FAILED(capture->GetNextPacketSize(&frames))) {
        // The device was unplugged or reconfigured. The engine hears about a removed device from the device list.
        running = false;
        break;
      }
      if (frames == 0) break;
      const HRESULT taken = capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
      if (FAILED(taken)) {
        running = false;
        break;
      }
      if (taken == AUDCLNT_S_BUFFER_EMPTY || frames == 0) {
        // Nothing after all. Hand the (empty) buffer back; whether that call is needed here is not documented, so
        // its answer is not an error either way.
        capture->ReleaseBuffer(0);
        break;
      }

      const std::size_t bytes = static_cast<std::size_t>(frames) * kBytesPerFrame;
      if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr) {
        // A silent packet: the buffer's contents mean nothing.
        block.assign(bytes, std::uint8_t{0});
      } else {
        block.assign(data, data + bytes);
      }
      if (FAILED(capture->ReleaseBuffer(frames))) {
        running = false;
        break;
      }
      level_db_.store(PeakDb(block));
      if (on_audio_) on_audio_(block.data(), block.size());
    }
  }
  level_db_.store(kSilenceDb);
}
