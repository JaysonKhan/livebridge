#include "livebridge/source_mixer.h"

#include <algorithm>
#include <atomic>
#include <limits>

namespace livebridge {

struct SourceMixer::Counters {
  explicit Counters(std::size_t input_count) : drops(input_count) {
    for (auto& counter : drops) counter.store(0, std::memory_order_relaxed);
  }
  std::vector<std::atomic<std::size_t>> drops;  // per input, written only by that input's producer
};

SourceMixer::SourceMixer(std::size_t input_count, std::size_t capacity, std::size_t max_lag)
    : max_lag_(max_lag), counters_(std::make_shared<Counters>(input_count)) {
  queues_.reserve(input_count);
  for (std::size_t i = 0; i < input_count; i++) queues_.push_back(std::make_unique<RingBuffer>(capacity));
}

std::size_t SourceMixer::push(std::size_t index, const float* samples, std::size_t count) {
  if (index >= queues_.size()) return 0;
  const std::size_t accepted = queues_[index]->write(samples, count);
  if (accepted < count) counters_->drops[index].fetch_add(count - accepted, std::memory_order_relaxed);
  return accepted;
}

std::size_t SourceMixer::mix(std::vector<float>& out) {
  if (queues_.empty()) return 0;
  std::size_t fewest = std::numeric_limits<std::size_t>::max();
  std::size_t most = 0;
  for (const auto& queue : queues_) {
    const std::size_t available = queue->available_to_read();
    fewest = std::min(fewest, available);
    most = std::max(most, available);
  }
  // Wait for the slowest input while it is within `max_lag`; beyond that it is silent for the samples it lacks.
  const std::size_t count = most - fewest <= max_lag_ ? fewest : most;
  if (count == 0) return 0;

  const std::size_t start = out.size();
  out.resize(start + count, 0.0f);
  float* mixed = out.data() + start;
  // The first input is read in place (a lone input in -1…1 passes through unchanged); the others are added to it.
  // Producers only add samples, so every input still has at least what it had above; a lagging one may give more.
  queues_[0]->read(mixed, count);
  std::vector<float> scratch(queues_.size() > 1 ? count : 0);
  for (std::size_t i = 1; i < queues_.size(); i++) {
    const std::size_t got = queues_[i]->read(scratch.data(), count);
    for (std::size_t k = 0; k < got; k++) mixed[k] += scratch[k];
  }
  for (std::size_t k = 0; k < count; k++) mixed[k] = std::clamp(mixed[k], -1.0f, 1.0f);
  return count;
}

std::size_t SourceMixer::dropped() const {
  std::size_t total = 0;
  for (const auto& counter : counters_->drops) total += counter.load(std::memory_order_relaxed);
  return total;
}

}  // namespace livebridge
