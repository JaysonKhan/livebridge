#ifndef RUNNER_WASAPI_SINK_H_
#define RUNNER_WASAPI_SINK_H_

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "livebridge/audio_dsp.h"
#include "livebridge/engine.h"
#include "livebridge/ring_buffer.h"

struct IAudioClient;
struct IAudioRenderClient;

// One shared-mode WASAPI playback on a render endpoint, fed with PCM s16le mono at any sample rate: the Windows twin
// of PlaybackSink in DeviceIO.swift. The stream itself is 48 kHz mono 16-bit; Windows converts that to the device's
// own mix format. What is written is resampled to 48 kHz and waits in a 30 s queue.
//
// Playback follows the macOS rules: a turn starts once 80 ms are queued, or at once when its input has ended; when the
// queue runs dry the gate closes again, which counts as an underrun unless the input had ended. While muted the queue
// keeps draining but the device plays silence. Mono goes to every channel (Windows' conversion) and samples are
// clamped to -1...1.
//
// Threads: Open(), Close() and every other method are called on one thread (the engine thread), the queue's
// producer. The render thread, owned by this object, is the queue's consumer; besides the queue it shares only atomics.
class WasapiSink {
 public:
  static constexpr int kSampleRate = 48'000;

  WasapiSink();
  ~WasapiSink();
  WasapiSink(const WasapiSink&) = delete;
  WasapiSink& operator=(const WasapiSink&) = delete;

  // Opens the endpoint and starts it playing silence; returns when the device runs or has refused. Once per object.
  // On failure `error` says why and nothing is left running.
  bool Open(const std::string& device_uid, livebridge::HostError& error);
  // Stops the device and joins the render thread. Safe to call again; the destructor calls it.
  void Close();

  // Queues PCM s16le mono recorded at `sample_rate`. False when the queue was full and audio was lost.
  bool Write(const std::uint8_t* pcm, std::size_t bytes, int sample_rate);
  // End of a turn: queues what the resamplers still hold, and lets the tail play without waiting to prebuffer.
  void EndInput();
  // Drops everything queued; the device plays silence from its next cycle.
  void Flush();
  void SetMuted(bool muted) { muted_.store(muted); }

  // 48 kHz samples queued so far, and taken by the device so far (flushed ones count as taken). Never decreasing.
  std::int64_t written() const { return ring_.written(); }
  std::int64_t consumed() const { return ring_.consumed(); }
  double queued_ms() const;
  // Mid-turn starvations (the network did not deliver in time). End-of-turn drains are not counted.
  std::int64_t underruns() const { return underruns_.load(); }

 private:
  // The render thread: opens the device, answers Open(), then feeds it until Close() or until the device fails.
  void Run(const std::wstring& device_id);
  // `ready` is the stream's event (a HANDLE).
  void Play(IAudioClient* client, IAudioRenderClient* render, void* ready, std::uint32_t buffer_frames);

  livebridge::RingBuffer ring_;
  std::atomic<bool> input_ended_{true};
  std::atomic<bool> muted_{false};
  std::atomic<std::int64_t> underruns_{0};
  std::atomic<bool> stop_{false};

  // Engine thread only: one resampler per input rate, and scratch space for Write().
  std::map<int, livebridge::Resampler> resamplers_;
  std::vector<std::int16_t> pcm_;
  std::vector<float> converted_;

  // How the render thread tells Open() that the device runs, or which step failed with which HRESULT.
  std::mutex start_mutex_;
  std::condition_variable start_answered_;
  bool start_done_ = false;
  long start_result_ = 0;
  const char* start_step_ = "";

  std::thread thread_;
};

#endif  // RUNNER_WASAPI_SINK_H_
