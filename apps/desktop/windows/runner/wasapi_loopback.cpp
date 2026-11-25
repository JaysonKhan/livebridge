#include "wasapi_loopback.h"

#include <windows.h>

#include <objbase.h>
#include <objidl.h>
#include <propidl.h>

#include <audioclient.h>
#include <audioclientactivationparams.h>
#include <avrt.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include "livebridge/audio_dsp.h"
#include "win_util.h"

// The device path that activates a process-loopback stream. Defined by the Windows SDK since build 20348; spelled out
// here for an SDK that declares the activation parameters but not this name.
#ifndef VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK
#define VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK L"VAD\\Process_Loopback"
#endif

namespace {

using Microsoft::WRL::ComPtr;

// How much the system may hold for us between reads: 200 ms, in units of 100 ns (a REFERENCE_TIME).
const REFERENCE_TIME kBufferDuration = 200 * 10'000;
// The stream signals its event whenever audio has arrived (silence included); the time-out, well within the buffer
// above, keeps the thread reading should it not.
const DWORD kWaitMs = 100;
// How long the system gets to activate a stream.
const DWORD kActivationTimeoutMs = 5'000;
// The first Windows build Microsoft documents process loopback for.
const unsigned long kFirstBuild = 20'348;
const double kSilenceDb = -120.0;

// The 16-bit PCM formats tried, in order. Which formats a process-loopback stream accepts is not documented: first the
// engine's own format through the system's converter, then the stereo formats of Microsoft's ApplicationLoopback
// sample, which arrive here as they are and are converted below.
struct Attempt {
  DWORD rate;
  WORD channels;
  DWORD extra_flags;
};
const Attempt kAttempts[] = {
    {16'000, 1, AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY},
    {44'100, 2, 0},
    {48'000, 2, 0},
};

WAVEFORMATEX Pcm16(const Attempt& attempt) {
  WAVEFORMATEX wave = {};
  wave.wFormatTag = WAVE_FORMAT_PCM;
  wave.nChannels = attempt.channels;
  wave.nSamplesPerSec = attempt.rate;
  wave.wBitsPerSample = 16;
  wave.nBlockAlign = static_cast<WORD>(attempt.channels * 2);
  wave.nAvgBytesPerSec = attempt.rate * wave.nBlockAlign;
  wave.cbSize = 0;
  return wave;
}

// The Windows build number, from RtlGetVersion: GetVersionExW is deprecated, and reports an older Windows to an app
// without a compatibility manifest. 0 when it cannot be read.
unsigned long WindowsBuild() {
  using RtlGetVersionFunction = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  const HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) return 0;
  const auto get_version = reinterpret_cast<RtlGetVersionFunction>(::GetProcAddress(ntdll, "RtlGetVersion"));
  if (get_version == nullptr) return 0;
  RTL_OSVERSIONINFOW info = {};
  info.dwOSVersionInfoSize = static_cast<DWORD>(sizeof(info));
  return get_version(&info) == 0 ? info.dwBuildNumber : 0UL;
}

// Receives the outcome of ActivateAudioInterfaceAsync. The system calls it on a worker thread of the multithreaded
// apartment, which is why it has to be agile (IAgileObject). Reference-counted: the system holds its own reference
// until it has called back, which may be after the waiting thread gave up; the last Release() deletes it.
class ActivationHandler final : public IActivateAudioInterfaceCompletionHandler, public IAgileObject {
 public:
  ActivationHandler() : done_(::CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (object == nullptr) return E_POINTER;
    if (IsEqualIID(iid, __uuidof(IUnknown)) || IsEqualIID(iid, __uuidof(IActivateAudioInterfaceCompletionHandler))) {
      *object = static_cast<IActivateAudioInterfaceCompletionHandler*>(this);
    } else if (IsEqualIID(iid, __uuidof(IAgileObject))) {
      *object = static_cast<IAgileObject*>(this);
    } else {
      *object = nullptr;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG left = --references_;
    if (left == 0) delete this;
    return left;
  }

  HRESULT STDMETHODCALLTYPE ActivateCompleted(IActivateAudioInterfaceAsyncOperation* operation) override {
    HRESULT activated = E_FAIL;
    ComPtr<IUnknown> unknown;
    HRESULT outcome = operation->GetActivateResult(&activated, unknown.GetAddressOf());
    if (SUCCEEDED(outcome)) outcome = activated;
    if (SUCCEEDED(outcome)) outcome = unknown.As(&client_);
    outcome_ = outcome;
    ::SetEvent(done_.get());
    return S_OK;
  }

  // Waits for ActivateCompleted. On success `client` is the activated stream, not initialised yet.
  HRESULT Wait(DWORD timeout_ms, ComPtr<IAudioClient>& client) {
    if (::WaitForSingleObject(done_.get(), timeout_ms) != WAIT_OBJECT_0) return HRESULT_FROM_WIN32(ERROR_TIMEOUT);
    if (SUCCEEDED(outcome_)) client = std::move(client_);
    return outcome_;
  }

 private:
  ~ActivationHandler() = default;

  std::atomic<ULONG> references_{1};
  ScopedHandle done_;
  // Written by ActivateCompleted before it signals `done_`, and read only after that.
  HRESULT outcome_ = E_FAIL;
  ComPtr<IAudioClient> client_;
};

// Activates a process-loopback stream on `process_id` and its child processes, and waits for it.
HRESULT Activate(DWORD process_id, ComPtr<IAudioClient>& client) {
  AUDIOCLIENT_ACTIVATION_PARAMS parameters = {};
  parameters.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
  parameters.ProcessLoopbackParams.TargetProcessId = process_id;
  parameters.ProcessLoopbackParams.ProcessLoopbackMode = PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE;
  // Points at `parameters`, so it is not cleared (PropVariantClear would free the blob).
  PROPVARIANT activation;
  PropVariantInit(&activation);
  activation.vt = VT_BLOB;
  activation.blob.cbSize = static_cast<ULONG>(sizeof(parameters));
  activation.blob.pBlobData = reinterpret_cast<BYTE*>(&parameters);

  // Our reference, released below; the system takes its own.
  ActivationHandler* handler = new ActivationHandler();
  ComPtr<IActivateAudioInterfaceAsyncOperation> operation;
  HRESULT result = ::ActivateAudioInterfaceAsync(VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient),
                                                 &activation, handler, operation.GetAddressOf());
  if (SUCCEEDED(result)) result = handler->Wait(kActivationTimeoutMs, client);
  handler->Release();
  return result;
}

// Activates the stream, finds a format it accepts, and starts it. On failure `step` names what was refused.
HRESULT OpenLoopback(DWORD process_id, HANDLE ready, ComPtr<IAudioClient>& client,
                     ComPtr<IAudioCaptureClient>& capture, Attempt& accepted, const char*& step) {
  HRESULT result = E_FAIL;
  for (const Attempt& attempt : kAttempts) {
    // A refused Initialize may leave a client unusable, so every attempt starts from a fresh activation.
    ComPtr<IAudioClient> candidate;
    step = "activating the capture";
    result = Activate(process_id, candidate);
    // Activation does not depend on the format: no point trying the others.
    if (FAILED(result)) return result;
    const WAVEFORMATEX wave = Pcm16(attempt);
    const DWORD stream_flags = AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK | attempt.extra_flags;
    step = "setting up the stream";
    result = candidate->Initialize(AUDCLNT_SHAREMODE_SHARED, stream_flags, kBufferDuration, 0, &wave, nullptr);
    if (SUCCEEDED(result)) {
      client = candidate;
      accepted = attempt;
      break;
    }
  }
  if (FAILED(result)) return result;
  step = "the stream's event";
  result = client->SetEventHandle(ready);
  if (FAILED(result)) return result;
  step = "the capture service";
  result = client->GetService(IID_PPV_ARGS(capture.GetAddressOf()));
  if (FAILED(result)) return result;
  step = "starting the stream";
  return client->Start();
}

}  // namespace

WasapiLoopback::~WasapiLoopback() { Stop(); }

bool WasapiLoopback::Start(int process_id, AudioCallback on_audio, livebridge::HostError& error) {
  Stop();
  const std::string gone =
      "The meeting app (process " + std::to_string(process_id) + ") is not running any more; pick it again.";
  if (process_id <= 0) {
    error = {"source_gone", gone};
    return false;
  }
  const DWORD pid = static_cast<DWORD>(process_id);
  const HANDLE process = ::OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  // A process that may not be opened (a protected one) exists; any other failure means it does not.
  const bool exists = process != nullptr || ::GetLastError() == ERROR_ACCESS_DENIED;
  process_.reset(process);
  if (!exists || !ProcessRunning()) {
    process_.reset();
    error = {"source_gone", gone};
    return false;
  }

  on_audio_ = std::move(on_audio);
  stop_.store(false);
  start_done_ = false;
  thread_ = std::thread([this, pid] { Run(pid); });

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
  process_.reset();
  // Microsoft does not document what an older Windows answers; on one, the missing feature is the likely reason.
  const unsigned long build = WindowsBuild();
  if (build != 0 && build < kFirstBuild) {
    error = {"source_unsupported",
             "Capturing one app's sound needs Windows 11 or Windows 10 build 20348 or newer (this PC: build " +
                 std::to_string(build) + ")."};
  } else {
    error = {"source_gone", std::string("The meeting app's sound cannot be captured (") + step + ", HRESULT " +
                                HexCode(static_cast<unsigned long>(result)) + "); pick the app again."};
  }
  return false;
}

void WasapiLoopback::Stop() {
  if (thread_.joinable()) {
    stop_.store(true);
    thread_.join();
  }
  on_audio_ = nullptr;
  process_.reset();
}

bool WasapiLoopback::ProcessRunning() const {
  return process_.get() == nullptr || ::WaitForSingleObject(process_.get(), 0) == WAIT_TIMEOUT;
}

void WasapiLoopback::Run(unsigned long process_id) {
  const HRESULT com = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    // In this scope, so that the stream is released before COM is; the event goes last, after the stream that
    // signals it.
    ScopedHandle ready(::CreateEventW(nullptr, FALSE, FALSE, nullptr));
    ComPtr<IAudioClient> client;
    ComPtr<IAudioCaptureClient> capture;
    Attempt accepted = {};
    const char* step = "COM";
    HRESULT result = com;
    // (Should the event be missing, SetEventHandle refuses it and that step is reported.)
    if (SUCCEEDED(result)) result = OpenLoopback(process_id, ready.get(), client, capture, accepted, step);
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
      Read(capture.Get(), ready.get(), static_cast<int>(accepted.rate), accepted.channels);
      if (priority != nullptr) ::AvRevertMmThreadCharacteristics(priority);
      // Nothing to do about a failure here: the stream is released right below.
      client->Stop();
    }
  }
  if (SUCCEEDED(com)) ::CoUninitialize();
}

void WasapiLoopback::Read(IAudioCaptureClient* capture, void* ready, int rate, int channels) {
  livebridge::Resampler resampler(rate, kSampleRate);
  std::vector<float> mono;
  std::vector<float> converted;
  bool running = true;
  while (running && !stop_.load()) {
    if (::WaitForSingleObject(ready, kWaitMs) == WAIT_FAILED) break;
    // Take every packet that has arrived since the last wake-up.
    for (;;) {
      UINT32 packet_frames = 0;
      if (FAILED(capture->GetNextPacketSize(&packet_frames))) {
        // The stream failed (its process ended, or the system reconfigured it). The engine's source watch notices
        // a process that has gone.
        running = false;
        break;
      }
      if (packet_frames == 0) break;
      BYTE* buffer = nullptr;
      UINT32 frames = 0;
      DWORD buffer_flags = 0;
      const HRESULT taken = capture->GetBuffer(&buffer, &frames, &buffer_flags, nullptr, nullptr);
      if (FAILED(taken)) {
        running = false;
        break;
      }
      if (taken == AUDCLNT_S_BUFFER_EMPTY || frames == 0) {
        // Nothing after all. As in wasapi_capture.cpp: whether this call is needed is not documented, so its answer
        // is not an error either way.
        capture->ReleaseBuffer(0);
        break;
      }

      mono.resize(frames);
      if ((buffer_flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || buffer == nullptr) {
        // A silent packet: the buffer's contents mean nothing.
        std::fill(mono.begin(), mono.end(), 0.0f);
      } else {
        livebridge::downmix_to_mono(reinterpret_cast<const std::int16_t*>(buffer), frames, channels, mono.data());
      }
      if (FAILED(capture->ReleaseBuffer(frames))) {
        running = false;
        break;
      }

      converted.clear();
      resampler.process(mono.data(), mono.size(), converted);
      if (converted.empty()) continue;
      level_db_.store(livebridge::level_db(converted.data(), converted.size()));
      if (on_audio_) on_audio_(converted.data(), converted.size());
    }
  }
  level_db_.store(kSilenceDb);
}
