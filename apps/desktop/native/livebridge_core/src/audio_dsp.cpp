#include "livebridge/audio_dsp.h"

#include <algorithm>
#include <cmath>
#include <numeric>

namespace livebridge {
namespace {

constexpr double kPi = 3.14159265358979323846;

// Filter design. The kernel spans 2 × kHalfSpan periods of the lower of the two rates: 32 taps per phase when
// upsampling, and proportionally more when downsampling, so the transition band keeps the same width relative to the
// output's Nyquist frequency (a fixed 32 input taps at 48 kHz -> 16 kHz would leave it half the band wide). The
// cutoff sits at kCutoff × the lower Nyquist frequency, and the Kaiser window keeps the stopband near -85 dB.
constexpr int kHalfSpan = 16;
constexpr double kCutoff = 0.9;
constexpr double kKaiserBeta = 8.6;

/// Modified Bessel function of the first kind, order 0 (its power series converges quickly for these betas).
double bessel_i0(double x) {
  const double quarter_x2 = x * x / 4;
  double sum = 1;
  double term = 1;
  for (int k = 1; k < 100 && term > sum * 1e-17; k++) {
    term *= quarter_x2 / (static_cast<double>(k) * k);
    sum += term;
  }
  return sum;
}

float dot(const float* taps, const float* samples, int count) {
  float sum = 0;
  for (int k = 0; k < count; k++) sum += taps[k] * samples[k];
  return sum;
}

double level_from_sum_of_squares(double sum, std::size_t count) {
  const double rms = std::sqrt(sum / static_cast<double>(count));
  return rms > 0 ? std::max(-120.0, 20 * std::log10(rms)) : -120;
}

}  // namespace

// The input is treated as upsampled by `up` (zeros between its samples), low-pass filtered and decimated by `down`.
// Output sample j sits at input position j × down / up = base + phase / up, and is the dot product of filter phase
// `phase` with the 2 × half input samples around that position, x[base - half + 1 … base + half]. The kernel is
// centred on the position, so the output is time-aligned with the input (an impulse at input n peaks at output
// n × up / down) with no group delay; the price is a look-ahead of `half` input samples, which `finish` supplies as
// silence at the end of a stream. Input before the start of a stream is silence too.
struct Resampler::State {
  bool passthrough = false;
  std::int64_t up = 1;
  std::int64_t down = 1;
  int half = 0;
  std::vector<float> bank;  // `up` phases × 2 × half taps, each phase summing to 1

  // The stream: input from absolute index `history_start` (negative: silence before the start) to `received`.
  std::vector<float> history;
  std::int64_t history_start = 0;
  std::int64_t received = 0;  // input samples in this stream
  std::int64_t emitted = 0;   // output samples in this stream
  std::int64_t base = 0;      // floor(emitted × down / up)
  std::int64_t phase = 0;     // emitted × down mod up

  void restart() {
    if (passthrough) return;
    history.assign(static_cast<std::size_t>(half - 1), 0.0f);
    history_start = -(half - 1);
    received = emitted = base = phase = 0;
  }

  /// Appends output sample `emitted`; every input sample under its kernel must be in `history`.
  void emit(std::vector<float>& out) {
    const std::size_t taps = static_cast<std::size_t>(2 * half);
    const std::size_t first = static_cast<std::size_t>(base - half + 1 - history_start);
    out.push_back(dot(bank.data() + static_cast<std::size_t>(phase) * taps, history.data() + first, 2 * half));
    emitted++;
    phase += down;
    base += phase / up;
    phase %= up;
  }
};

void Resampler::StateDeleter::operator()(State* state) const { delete state; }

Resampler::Resampler(int in_rate, int out_rate) : input_rate_(in_rate), output_rate_(out_rate), state_(new State) {
  State& s = *state_;
  // Equal rates copy samples unchanged; so does a rate that is not positive, rather than dividing by zero.
  if (in_rate <= 0 || out_rate <= 0 || in_rate == out_rate) {
    s.passthrough = true;
    return;
  }
  const int common = std::gcd(in_rate, out_rate);
  s.up = out_rate / common;
  s.down = in_rate / common;
  // Downsampling by r = down / up stretches the kernel (in input samples) and lowers the cutoff by r.
  const double ratio = std::max(1.0, static_cast<double>(s.down) / static_cast<double>(s.up));
  s.half = static_cast<int>(std::ceil(kHalfSpan * ratio));
  const int taps = 2 * s.half;
  const double cutoff = kCutoff * 0.5 / ratio;  // cycles per input sample
  const double window_scale = 1 / bessel_i0(kKaiserBeta);
  s.bank.resize(static_cast<std::size_t>(s.up) * static_cast<std::size_t>(taps));
  std::vector<double> phase_taps(static_cast<std::size_t>(taps));
  for (std::int64_t phase = 0; phase < s.up; phase++) {
    double sum = 0;
    for (int k = 0; k < taps; k++) {
      // Distance from input sample base - half + 1 + k to the output position base + phase / up: -half … half.
      const double t = static_cast<double>(phase) / static_cast<double>(s.up) + (s.half - 1 - k);
      const double x = 2 * cutoff * t;
      const double sinc = x == 0 ? 1.0 : std::sin(kPi * x) / (kPi * x);
      const double r = t / s.half;
      const double window = bessel_i0(kKaiserBeta * std::sqrt(std::max(0.0, 1 - r * r))) * window_scale;
      phase_taps[static_cast<std::size_t>(k)] = sinc * window;
      sum += sinc * window;
    }
    // Unit gain at DC in every phase: a constant input gives a constant output, without ripple at the phase rate.
    float* dest = s.bank.data() + static_cast<std::size_t>(phase) * static_cast<std::size_t>(taps);
    for (std::size_t k = 0; k < phase_taps.size(); k++) dest[k] = static_cast<float>(phase_taps[k] / sum);
  }
  s.restart();
}

void Resampler::process(const float* in, std::size_t count, std::vector<float>& out) {
  if (count == 0) return;
  State& s = *state_;
  if (s.passthrough) {
    out.insert(out.end(), in, in + count);
    return;
  }
  s.history.insert(s.history.end(), in, in + count);
  s.received += static_cast<std::int64_t>(count);
  // An output sample is ready once the last input sample under its kernel has arrived.
  while (s.base + s.half < s.received) s.emit(out);
  // Forget the input that no later output reaches back to.
  const std::int64_t unused = s.base - s.half + 1 - s.history_start;
  if (unused > 0) {
    s.history.erase(s.history.begin(), s.history.begin() + static_cast<std::ptrdiff_t>(unused));
    s.history_start += unused;
  }
}

void Resampler::process(const std::int16_t* in, std::size_t count, std::vector<float>& out) {
  std::vector<float> samples(count);
  int16_to_float(in, count, samples.data());
  process(samples.data(), count, out);
}

void Resampler::finish(std::vector<float>& out) {
  State& s = *state_;
  if (s.passthrough) return;
  // The whole stream is round(received × up / down) samples long at the output rate.
  const std::int64_t total = (2 * s.received * s.up + s.down) / (2 * s.down);
  if (s.emitted < total) {
    // Silence after the end of the stream fills the look-ahead of the last outputs (all within `half` samples).
    s.history.insert(s.history.end(), static_cast<std::size_t>(s.half), 0.0f);
    while (s.emitted < total) s.emit(out);
  }
  s.restart();
}

void Resampler::reset() { state_->restart(); }

void int16_to_float(const std::int16_t* in, std::size_t count, float* out) {
  for (std::size_t i = 0; i < count; i++) out[i] = static_cast<float>(in[i]) * (1.0f / 32768);
}

void float_to_int16(const float* in, std::size_t count, std::int16_t* out) {
  for (std::size_t i = 0; i < count; i++) {
    const double scaled = static_cast<double>(in[i]) * 32768;
    if (std::isnan(scaled)) {
      out[i] = 0;
      continue;
    }
    out[i] = static_cast<std::int16_t>(std::lround(std::clamp(scaled, -32768.0, 32767.0)));
  }
}

void downmix_to_mono(const float* in, std::size_t frames, int channels, float* out) {
  if (channels < 1) {
    std::fill(out, out + frames, 0.0f);
    return;
  }
  if (channels == 1) {
    std::copy(in, in + frames, out);
    return;
  }
  const std::size_t stride = static_cast<std::size_t>(channels);
  const float scale = 1.0f / static_cast<float>(channels);
  for (std::size_t frame = 0; frame < frames; frame++) {
    float sum = 0;
    for (std::size_t channel = 0; channel < stride; channel++) sum += in[frame * stride + channel];
    out[frame] = sum * scale;
  }
}

void downmix_to_mono(const std::int16_t* in, std::size_t frames, int channels, float* out) {
  if (channels < 1) {
    std::fill(out, out + frames, 0.0f);
    return;
  }
  const std::size_t stride = static_cast<std::size_t>(channels);
  const float scale = 1.0f / (32768.0f * static_cast<float>(channels));
  for (std::size_t frame = 0; frame < frames; frame++) {
    std::int64_t sum = 0;
    for (std::size_t channel = 0; channel < stride; channel++) sum += in[frame * stride + channel];
    out[frame] = static_cast<float>(sum) * scale;
  }
}

double level_db(const std::int16_t* samples, std::size_t count) {
  if (count == 0) return -120;
  double sum = 0;
  for (std::size_t i = 0; i < count; i++) {
    const double sample = samples[i] / 32768.0;
    sum += sample * sample;
  }
  return level_from_sum_of_squares(sum, count);
}

double level_db(const float* samples, std::size_t count) {
  if (count == 0) return -120;
  double sum = 0;
  for (std::size_t i = 0; i < count; i++) {
    const double sample = samples[i];
    sum += sample * sample;
  }
  return level_from_sum_of_squares(sum, count);
}

}  // namespace livebridge
