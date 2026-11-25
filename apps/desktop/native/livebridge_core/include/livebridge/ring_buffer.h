// Bounded single-producer / single-consumer ring of float samples (the C++ twin of the Swift RingBuffer).
//
// `write` may be called from exactly one thread and `read` from exactly one other (the real-time audio thread).
// Neither side locks, allocates or blocks. `flush` is called by the producer side and takes effect on the
// consumer's next read, which is how panic-stop empties a playback queue without touching the audio thread.
#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>

namespace livebridge {

class RingBuffer {
 public:
  explicit RingBuffer(std::size_t capacity)
      : capacity_(static_cast<std::int64_t>(capacity)), storage_(new float[capacity]()) {}

  RingBuffer(const RingBuffer&) = delete;
  RingBuffer& operator=(const RingBuffer&) = delete;

  std::size_t capacity() const { return static_cast<std::size_t>(capacity_); }

  /// Total samples ever written. Producer side.
  std::int64_t written() const { return write_.load(std::memory_order_acquire); }

  /// Total samples ever consumed (read or flushed past). Safe from any thread.
  std::int64_t consumed() const {
    return std::max(read_.load(std::memory_order_acquire), flush_.load(std::memory_order_acquire));
  }

  std::size_t available_to_read() const {
    return static_cast<std::size_t>(std::max<std::int64_t>(0, written() - consumed()));
  }

  /// Producer. Copies as many samples as fit and returns that count; the rest are the caller's overflow.
  std::size_t write(const float* source, std::size_t count) {
    const std::int64_t write = write_.load(std::memory_order_relaxed);
    const std::int64_t free = capacity_ - (write - consumed());
    const std::int64_t n = std::min<std::int64_t>(static_cast<std::int64_t>(count), std::max<std::int64_t>(0, free));
    if (n <= 0) return 0;
    const std::int64_t start = write % capacity_;
    const std::int64_t first = std::min(n, capacity_ - start);
    std::memcpy(storage_.get() + start, source, static_cast<std::size_t>(first) * sizeof(float));
    if (n > first) std::memcpy(storage_.get(), source + first, static_cast<std::size_t>(n - first) * sizeof(float));
    write_.store(write + n, std::memory_order_release);
    return static_cast<std::size_t>(n);
  }

  /// Consumer (real-time safe). Copies up to `count` samples and returns how many were available.
  std::size_t read(float* destination, std::size_t count) {
    std::int64_t read = read_.load(std::memory_order_relaxed);
    const std::int64_t flush = flush_.load(std::memory_order_acquire);
    if (flush > read) read = flush;
    const std::int64_t available = write_.load(std::memory_order_acquire) - read;
    const std::int64_t n = std::min<std::int64_t>(static_cast<std::int64_t>(count), std::max<std::int64_t>(0, available));
    if (n > 0) {
      const std::int64_t start = read % capacity_;
      const std::int64_t first = std::min(n, capacity_ - start);
      std::memcpy(destination, storage_.get() + start, static_cast<std::size_t>(first) * sizeof(float));
      if (n > first) std::memcpy(destination + first, storage_.get(), static_cast<std::size_t>(n - first) * sizeof(float));
    }
    read_.store(read + n, std::memory_order_release);
    return static_cast<std::size_t>(n);
  }

  /// Producer. Discards everything written so far; the consumer skips it on its next read.
  void flush() { flush_.store(write_.load(std::memory_order_relaxed), std::memory_order_release); }

 private:
  const std::int64_t capacity_;
  const std::unique_ptr<float[]> storage_;
  // Monotonic sample positions; the buffer index is `position % capacity`.
  std::atomic<std::int64_t> write_{0};
  std::atomic<std::int64_t> read_{0};
  std::atomic<std::int64_t> flush_{0};
};

}  // namespace livebridge
