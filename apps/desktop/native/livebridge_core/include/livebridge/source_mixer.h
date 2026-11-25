// Mixes several live mono streams of the same sample rate into one: the meeting source on Windows can be more than
// one process, each captured on its own thread. Every input is a lock-free single-producer/single-consumer queue:
// input i is written by exactly one thread (its capture thread), and `mix` is called by exactly one other thread
// (the engine thread).
#pragma once

#include <cstddef>
#include <memory>
#include <vector>

#include "livebridge/ring_buffer.h"

namespace livebridge {

class SourceMixer {
 public:
  /// `inputs` streams; each queue holds up to `capacity` samples (what does not fit is dropped and counted).
  /// `max_lag` samples: how far the fastest input may run ahead of a silent or stalled one before the stalled one is
  /// treated as silence, so one dead process cannot hold back the others for more than that.
  SourceMixer(std::size_t inputs, std::size_t capacity, std::size_t max_lag);

  std::size_t inputs() const { return queues_.size(); }

  /// Producer side of input `index` (its own thread). Returns how many samples were accepted.
  std::size_t push(std::size_t index, const float* samples, std::size_t count);

  /// Consumer side. Appends to `out` as many mixed samples as every input can provide (the sum of the inputs,
  /// clamped to -1…1) — or, when an input lags by more than `max_lag`, as many as the fullest input can provide,
  /// with the lagging inputs contributing what they have and silence after it. Returns the number appended.
  std::size_t mix(std::vector<float>& out);

  /// Samples dropped because an input queue was full, over all inputs. Safe from any thread.
  std::size_t dropped() const;

 private:
  std::vector<std::unique_ptr<RingBuffer>> queues_;
  std::size_t max_lag_;
  // Implementation detail: per-input drop counters live in the .cpp (atomic).
  struct Counters;
  std::shared_ptr<Counters> counters_;
};

}  // namespace livebridge
