#ifndef RUNNER_WASAPI_LOOPBACK_H_
#define RUNNER_WASAPI_LOOPBACK_H_

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <functional>
#include <mutex>
#include <thread>

#include "livebridge/engine.h"
#include "scoped_handle.h"

struct IAudioCaptureClient;

// Captures what one process, and the processes it started, plays - nothing else on the system - through WASAPI's
// process loopback: the Windows counterpart of the process tap in ProcessTap.swift. Delivered as 16 kHz mono float.
// Microsoft documents it from Windows 10 build 20348 (Windows 11 has it).
//
// Start(), Stop() and ProcessRunning() are called on one thread (the engine thread). The capture thread, owned by
// this object, activates and reads the stream and calls `on_audio`; that callback must return quickly and must not
// call Stop().
class WasapiLoopback {
 public:
  static constexpr int kSampleRate = 16'000;

  // Whole samples of 16 kHz mono float in -1...1; the pointer is valid during the call only.
  using AudioCallback = std::function<void(const float* samples, std::size_t sample_count)>;

  WasapiLoopback() = default;
  ~WasapiLoopback();
  WasapiLoopback(const WasapiLoopback&) = delete;
  WasapiLoopback& operator=(const WasapiLoopback&) = delete;

  // Starts capturing process `process_id`; returns when the stream runs or has been refused. `on_audio` may be empty,
  // for a capture that only feeds a level meter. On failure `error` says why - `source_unsupported` on a Windows
  // without process loopback, `source_gone` otherwise - and nothing is left running.
  bool Start(int process_id, AudioCallback on_audio, livebridge::HostError& error);

  // Stops capturing and joins the capture thread: `on_audio` is not called after this returns. Safe to call again.
  void Stop();

  // RMS level of the audio delivered last, in dBFS: -120 for silence, and while nothing is being captured.
  double level_db() const { return level_db_.load(); }

  // False once the captured process has ended. (A process that may not be watched counts as running.)
  bool ProcessRunning() const;

 private:
  // The capture thread: activates the stream, answers Start(), then reads until Stop() or until the stream fails.
  void Run(unsigned long process_id);
  // `ready` is the stream's event (a HANDLE); `rate` and `channels` describe the 16-bit format the stream accepted.
  void Read(IAudioCaptureClient* capture, void* ready, int rate, int channels);

  AudioCallback on_audio_;
  std::atomic<bool> stop_{false};
  std::atomic<double> level_db_{-120.0};
  // Engine thread only. Held while capturing: it tells when the process ends, and keeps its id from being reused.
  ScopedHandle process_;

  // How the capture thread tells Start() that the stream runs, or which step failed with which HRESULT.
  std::mutex start_mutex_;
  std::condition_variable start_answered_;
  bool start_done_ = false;
  long start_result_ = 0;
  const char* start_step_ = "";

  std::thread thread_;
};

#endif  // RUNNER_WASAPI_LOOPBACK_H_
