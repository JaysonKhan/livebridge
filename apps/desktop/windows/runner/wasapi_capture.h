#ifndef RUNNER_WASAPI_CAPTURE_H_
#define RUNNER_WASAPI_CAPTURE_H_

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>

#include "livebridge/engine.h"

struct IAudioCaptureClient;

// One shared-mode WASAPI capture of an input endpoint, delivered as PCM s16le 16 kHz mono: the format the engine
// wants. Windows converts from whatever the device's own mix format is.
//
// Start() and Stop() are called on one thread (the engine thread). Everything that touches the device happens on
// the capture thread, which also calls `on_audio`: that callback must return quickly and must not call Stop().
class WasapiCapture {
 public:
  // Whole samples of PCM s16le 16 kHz mono; the pointer is valid during the call only.
  using AudioCallback = std::function<void(const std::uint8_t* pcm, std::size_t bytes)>;

  WasapiCapture() = default;
  ~WasapiCapture();
  WasapiCapture(const WasapiCapture&) = delete;
  WasapiCapture& operator=(const WasapiCapture&) = delete;

  // Opens the endpoint and starts capturing; returns when the device runs or has refused. `on_audio` may be empty,
  // for a capture that only feeds a level meter. On failure `error` says why and nothing is left running.
  bool Start(const std::string& device_uid, AudioCallback on_audio, livebridge::HostError& error);

  // Stops capturing and joins the capture thread: `on_audio` is not called after this returns. Safe to call again.
  void Stop();

  // Peak of the block delivered last, in dBFS: -120 for silence, and while nothing is being captured.
  double level_db() const { return level_db_.load(); }

 private:
  // The capture thread: opens the device, answers Start(), then polls until Stop() or until the device fails.
  void Run(const std::wstring& device_id);
  void Poll(IAudioCaptureClient* capture);

  AudioCallback on_audio_;
  std::atomic<bool> stop_{false};
  std::atomic<double> level_db_{-120.0};

  // How the capture thread tells Start() that the device runs, or which step failed with which HRESULT.
  std::mutex start_mutex_;
  std::condition_variable start_answered_;
  bool start_done_ = false;
  long start_result_ = 0;
  const char* start_step_ = "";

  std::thread thread_;
};

#endif  // RUNNER_WASAPI_CAPTURE_H_
