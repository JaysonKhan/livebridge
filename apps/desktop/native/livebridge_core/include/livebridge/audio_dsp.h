// Sample-rate conversion and small sample utilities shared by the platform layers (the C++ twin of Resampler.swift
// and its helpers). Nothing here allocates on its own except `Resampler::process`, which appends to a vector, so
// call it from worker threads, never from a real-time audio callback.
#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace livebridge {

/// Streaming mono sample-rate converter for any two positive rates (16 000, 22 050, 24 000, 44 100, 48 000, ...).
/// One instance per stream: it keeps its filter state between calls, so consecutive chunks join without clicks, and
/// converting a stream in chunks gives the same samples as converting it in one piece.
///
/// Quality: a windowed-sinc low-pass at the lower of the two Nyquist frequencies, so downsampling does not alias.
/// Equal rates pass samples through unchanged. Over a whole stream (`process` calls, then `finish`) the number of
/// output samples is the input count × output_rate / input_rate, rounded to the nearest sample.
class Resampler {
 public:
  Resampler(int input_rate, int output_rate);

  int input_rate() const { return input_rate_; }
  int output_rate() const { return output_rate_; }

  /// Converts `count` samples and appends the result to `out`. Float samples are nominally in -1…1.
  void process(const float* in, std::size_t count, std::vector<float>& out);
  /// The same, from PCM s16 (scaled by 1/32768).
  void process(const std::int16_t* in, std::size_t count, std::vector<float>& out);

  /// Ends the stream: appends what the filter still holds (otherwise cut off the end of a turn), then forgets it.
  void finish(std::vector<float>& out);
  /// Forgets the filter history without emitting it (a cancelled turn: the held samples must not be heard).
  void reset();

 private:
  int input_rate_;
  int output_rate_;
  // Implementation state (filter bank, history, phase, sample counters) is defined in audio_dsp.cpp.
  struct State;
  struct StateDeleter {
    void operator()(State* state) const;
  };
  std::unique_ptr<State, StateDeleter> state_;
};

/// PCM s16 -> float in -1…1.
void int16_to_float(const std::int16_t* in, std::size_t count, float* out);
/// Float -> PCM s16, rounded to nearest and clamped (values beyond -1…1 saturate instead of wrapping).
void float_to_int16(const float* in, std::size_t count, std::int16_t* out);
/// Interleaved multi-channel float -> mono (the mean of the channels). `out` holds `frames` samples.
void downmix_to_mono(const float* in, std::size_t frames, int channels, float* out);
/// Interleaved multi-channel PCM s16 -> mono float (the mean of the channels).
void downmix_to_mono(const std::int16_t* in, std::size_t frames, int channels, float* out);
/// RMS level in dBFS, floored at -120 (also for an empty block).
double level_db(const std::int16_t* samples, std::size_t count);
double level_db(const float* samples, std::size_t count);

}  // namespace livebridge
