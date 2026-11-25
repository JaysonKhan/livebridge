// Tests of the sample-rate converter, the sample utilities and the source mixer.
// Usage: dsp_tests [anything]   (every test program is given the frame fixtures' path; this one does not need it)
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <numeric>
#include <thread>
#include <vector>

#include "check.h"
#include "livebridge/audio_dsp.h"
#include "livebridge/source_mixer.h"

using namespace livebridge;

static constexpr double kPi = 3.14159265358979323846;

struct Rates {
  int in;
  int out;
};

// The conversions the platforms use, plus one (48 000 -> 44 100) whose length can round half a sample.
static const Rates kRates[] = {{16000, 48000}, {24000, 48000}, {48000, 16000},
                               {44100, 16000}, {22050, 48000}, {48000, 44100}};

// Odd and tiny input lengths (0 and 1 included).
static const std::size_t kLengths[] = {0, 1, 2, 3, 7, 80, 101, 1001, 4801, 44101};

static std::size_t expected_length(std::size_t input, const Rates& rates) {
  return static_cast<std::size_t>(std::llround(static_cast<double>(input) * rates.out / rates.in));
}

static std::vector<float> noise(std::size_t count, std::uint32_t seed) {
  std::vector<float> samples(count);
  for (float& sample : samples) {
    seed = seed * 1664525u + 1013904223u;
    sample = static_cast<float>(seed >> 8) / 16777216.0f - 0.5f;
  }
  return samples;
}

static std::vector<float> sine(std::size_t count, double frequency, double rate, double amplitude) {
  std::vector<float> samples(count);
  for (std::size_t i = 0; i < count; i++)
    samples[i] = static_cast<float>(amplitude * std::sin(2 * kPi * frequency * static_cast<double>(i) / rate + 0.3));
  return samples;
}

/// Converts `input` as one stream, fed in chunks of the given sizes (cycled), then finished.
static std::vector<float> convert(const Rates& rates, const std::vector<float>& input,
                                  const std::vector<std::size_t>& chunks) {
  Resampler resampler(rates.in, rates.out);
  std::vector<float> out;
  std::size_t at = 0;
  for (std::size_t i = 0; at < input.size(); i++) {
    const std::size_t count = std::min(chunks[i % chunks.size()], input.size() - at);
    resampler.process(input.data() + at, count, out);
    at += count;
  }
  resampler.finish(out);
  return out;
}

static std::vector<float> convert(const Rates& rates, const std::vector<float>& input) {
  return convert(rates, input, {std::max<std::size_t>(input.size(), 1)});
}

/// Amplitude of the `frequency` component of samples [from, to) (a single DFT bin; use whole periods).
static double tone_amplitude(const std::vector<float>& samples, std::size_t from, std::size_t to, double frequency,
                             double rate) {
  double re = 0;
  double im = 0;
  for (std::size_t i = from; i < to; i++) {
    const double phase = 2 * kPi * frequency * static_cast<double>(i) / rate;
    re += samples[i] * std::cos(phase);
    im += samples[i] * std::sin(phase);
  }
  return 2 * std::sqrt(re * re + im * im) / static_cast<double>(to - from);
}

static int zero_crossings(const std::vector<float>& samples, std::size_t from, std::size_t to) {
  int crossings = 0;
  for (std::size_t i = from + 1; i < to; i++)
    if ((samples[i - 1] < 0) != (samples[i] < 0)) crossings++;
  return crossings;
}

static std::size_t peak_index(const std::vector<float>& samples) {
  std::size_t peak = 0;
  for (std::size_t i = 1; i < samples.size(); i++)
    if (std::fabs(samples[i]) > std::fabs(samples[peak])) peak = i;
  return peak;
}

// ── Resampler ──

static void test_equal_rates_pass_through_exactly() {
  std::vector<float> input = noise(1001, 1);
  input[3] = 1.5f;  // even out-of-range samples are copied, not filtered or clamped
  input[4] = -2.0f;
  Resampler resampler(48000, 48000);
  std::vector<float> out;
  resampler.process(input.data(), 500, out);
  resampler.process(input.data() + 500, 501, out);
  resampler.finish(out);
  CHECK(out == input);
  CHECK(resampler.input_rate() == 48000 && resampler.output_rate() == 48000);

  const std::int16_t pcm[4] = {0, 16384, -32768, 32767};
  out.clear();
  resampler.process(pcm, 4, out);
  resampler.reset();
  CHECK(out == std::vector<float>({0.0f, 0.5f, -1.0f, 32767.0f / 32768}));
}

static void test_length_follows_the_rate_ratio() {
  for (const Rates& rates : kRates) {
    for (std::size_t count : kLengths) {
      const std::vector<float> input = noise(count, 3);
      CHECK(convert(rates, input).size() == expected_length(count, rates));
      // `process` alone holds back the look-ahead and never overshoots the whole stream's length.
      Resampler resampler(rates.in, rates.out);
      std::vector<float> out;
      resampler.process(input.data(), input.size(), out);
      CHECK(out.size() <= expected_length(count, rates));
    }
  }
  // 80 samples at 48 kHz are 73.5 at 44.1 kHz: rounded up.
  CHECK(convert({48000, 44100}, noise(80, 4)).size() == 74);
}

static void test_chunked_conversion_matches_one_shot() {
  const std::vector<std::vector<std::size_t>> patterns = {{1}, {7}, {160}, {441, 13, 0, 1, 2048}, {4800, 1}, {2, 3}};
  for (const Rates& rates : kRates) {
    const std::vector<float> input = noise(4801, 5);
    const std::vector<float> whole = convert(rates, input);
    for (const auto& pattern : patterns) CHECK(convert(rates, input, pattern) == whole);
  }
}

static void test_a_tone_keeps_its_level_and_frequency() {
  // One second of a 1 kHz tone; measured over half a second (whole periods) away from the stream's edges.
  for (const Rates& rates : kRates) {
    const std::vector<float> input = sine(static_cast<std::size_t>(rates.in), 1000, rates.in, 0.5);
    const std::vector<float> out = convert(rates, input);
    const std::size_t from = static_cast<std::size_t>(rates.out / 10);
    const std::size_t to = from + static_cast<std::size_t>(rates.out / 2);
    const double gain_db = 20 * std::log10(tone_amplitude(out, from, to, 1000, rates.out) / 0.5);
    CHECK(std::fabs(gain_db) <= 0.5);
    // All of the level is in that tone (RMS of a 0.5 sine: -9.03 dBFS), and it still crosses zero 2000 times/s.
    CHECK(std::fabs(level_db(out.data() + from, to - from) - 20 * std::log10(0.5 / std::sqrt(2.0))) <= 0.5);
    CHECK(std::abs(zero_crossings(out, from, to) - 1000) <= 2);
  }
}

static void test_downsampling_rejects_what_would_alias() {
  // A 10 kHz tone is above the 8 kHz Nyquist frequency of 16 kHz: it must be filtered out, not folded to 6 kHz.
  for (const Rates& rates : {Rates{48000, 16000}, Rates{44100, 16000}}) {
    const std::vector<float> input = sine(static_cast<std::size_t>(rates.in), 10000, rates.in, 0.5);
    const std::vector<float> out = convert(rates, input);
    const double input_db = level_db(input.data(), input.size());
    const double output_db = level_db(out.data() + 200, out.size() - 400);
    CHECK(input_db - output_db >= 40);
  }
}

static void test_an_impulse_stays_in_place() {
  for (const Rates& rates : kRates) {
    const std::size_t count = static_cast<std::size_t>(rates.in / 4);
    for (std::size_t at : {std::size_t{0}, count / 2 + 1, count / 3}) {
      std::vector<float> input(count, 0.0f);
      input[at] = 1.0f;
      const double expected = static_cast<double>(at) * rates.out / rates.in;
      CHECK(std::fabs(static_cast<double>(peak_index(convert(rates, input))) - expected) <= 1);
    }
  }
}

static void test_finish_keeps_the_end_of_the_stream() {
  for (const Rates& rates : kRates) {
    const std::size_t down = static_cast<std::size_t>(rates.in / std::gcd(rates.in, rates.out));
    const std::size_t up = static_cast<std::size_t>(rates.out / std::gcd(rates.in, rates.out));

    // An impulse on the very last input sample comes out exactly like the same impulse mid-stream (at the same
    // filter phase), up to the stream's last output sample.
    const std::size_t count = static_cast<std::size_t>(rates.in / 5);
    const std::size_t steps = count / 2 / down;  // the mid-stream impulse is steps × down input samples earlier
    std::vector<float> at_end(count, 0.0f);
    std::vector<float> mid(count, 0.0f);
    at_end[count - 1] = 1.0f;
    mid[count - 1 - steps * down] = 1.0f;
    const std::vector<float> out_end = convert(rates, at_end);
    const std::vector<float> out_mid = convert(rates, mid);
    CHECK(out_end.size() == expected_length(count, rates));
    const std::size_t tail = std::min<std::size_t>(out_end.size(), 64 * up / down + 8);
    bool same = true;
    float tail_peak = 0;
    for (std::size_t j = out_end.size() - tail; j < out_end.size(); j++) {
      same = same && out_end[j] == out_mid[j - steps * up];
      tail_peak = std::max(tail_peak, std::fabs(out_end[j]));
    }
    CHECK(same);
    CHECK(tail_peak > 0.1f);

    // A block of 1.0 stays at 1.0 up to its last input samples, then rolls off; nothing of it is cut short.
    const std::vector<float> ones(count, 1.0f);
    Resampler resampler(rates.in, rates.out);
    std::vector<float> out;
    resampler.process(ones.data(), ones.size(), out);
    const std::size_t held_back = out.size();
    resampler.finish(out);
    CHECK(out.size() == expected_length(count, rates));
    CHECK(out.size() > held_back);
    const std::size_t edge = 64 * up / down + 2;  // more than half a kernel, in output samples
    float worst = 0;
    double sum = 0;
    for (std::size_t j = 0; j < out.size(); j++) {
      if (j >= edge && j + edge < out.size()) worst = std::max(worst, std::fabs(out[j] - 1.0f));
      sum += out[j];
    }
    CHECK(worst < 1e-4f);
    CHECK(out.back() > 0.25f);
    // The output's area is the input's (at the output rate), less a fraction of a sample at either edge.
    const double ratio = static_cast<double>(rates.in) / rates.out;
    CHECK(std::fabs(sum * ratio - static_cast<double>(count)) < 2 + ratio);
  }
}

static void test_finish_and_reset_start_a_new_stream() {
  const Rates rates{44100, 16000};
  const std::vector<float> a = noise(3001, 7);
  const std::vector<float> b = noise(2003, 9);
  const std::vector<float> a_out = convert(rates, a);
  const std::vector<float> b_out = convert(rates, b);
  Resampler resampler(rates.in, rates.out);
  std::vector<float> out;
  resampler.finish(out);  // nothing was converted: nothing to flush
  CHECK(out.empty());
  resampler.process(a.data(), a.size(), out);
  resampler.finish(out);
  CHECK(out == a_out);
  out.clear();
  resampler.process(b.data(), b.size(), out);
  resampler.finish(out);
  CHECK(out == b_out);

  // A cancelled stream: reset drops what the filter holds, and a finish after it has nothing left to emit.
  out.clear();
  resampler.process(a.data(), a.size(), out);
  const std::size_t emitted = out.size();
  CHECK(emitted < a_out.size());
  resampler.reset();
  resampler.finish(out);
  CHECK(out.size() == emitted);
  out.clear();
  resampler.process(b.data(), b.size(), out);
  resampler.finish(out);
  CHECK(out == b_out);
}

static void test_int16_input_is_scaled() {
  std::vector<std::int16_t> pcm(1001);
  std::uint32_t seed = 11;
  for (std::int16_t& sample : pcm) {
    seed = seed * 1664525u + 1013904223u;
    sample = static_cast<std::int16_t>(static_cast<std::int32_t>(seed >> 16) - 32768);
  }
  pcm[0] = -32768;
  pcm[1] = 32767;
  std::vector<float> scaled(pcm.size());
  for (std::size_t i = 0; i < pcm.size(); i++) scaled[i] = static_cast<float>(pcm[i]) / 32768;
  Resampler from_pcm(24000, 48000);
  std::vector<float> out;
  from_pcm.process(pcm.data(), 600, out);
  from_pcm.process(pcm.data() + 600, pcm.size() - 600, out);
  from_pcm.finish(out);
  CHECK(out == convert({24000, 48000}, scaled));
}

// ── Sample utilities ──

static void test_sample_conversions_round_and_clamp() {
  const std::int16_t pcm[5] = {-32768, -1, 0, 1, 32767};
  float floats[5];
  int16_to_float(pcm, 5, floats);
  CHECK(floats[0] == -1.0f && floats[1] == -1.0f / 32768 && floats[2] == 0.0f && floats[3] == 1.0f / 32768);
  CHECK(floats[4] == 32767.0f / 32768);

  const float nan = std::numeric_limits<float>::quiet_NaN();
  const float inf = std::numeric_limits<float>::infinity();
  const float in[13] = {1.0f, -1.0f, 2.0f, -3.0f, inf, -inf, nan, 0.5f, 0.49f / 32768, 0.51f / 32768, -0.51f / 32768,
                        100.4f / 32768, -0.0f};
  const std::int16_t expected[13] = {32767, -32768, 32767, -32768, 32767, -32768, 0, 16384, 0, 1, -1, 100, 0};
  std::int16_t out[13];
  float_to_int16(in, 13, out);
  bool all = true;
  for (int i = 0; i < 13; i++) all = all && out[i] == expected[i];
  CHECK(all);

  // Every s16 value survives a round trip through float.
  std::vector<std::int16_t> every(65536);
  for (std::size_t i = 0; i < every.size(); i++) every[i] = static_cast<std::int16_t>(static_cast<int>(i) - 32768);
  std::vector<float> as_float(every.size());
  std::vector<std::int16_t> back(every.size());
  int16_to_float(every.data(), every.size(), as_float.data());
  float_to_int16(as_float.data(), as_float.size(), back.data());
  CHECK(back == every);
}

static void test_downmix_takes_the_mean_of_the_channels() {
  const float stereo[6] = {1.0f, 0.5f, -1.0f, 1.0f, 0.25f, 0.25f};
  float mono[3];
  downmix_to_mono(stereo, 3, 2, mono);
  CHECK(mono[0] == 0.75f && mono[1] == 0.0f && mono[2] == 0.25f);
  downmix_to_mono(stereo, 3, 1, mono);  // one channel: a copy
  CHECK(mono[0] == 1.0f && mono[1] == 0.5f && mono[2] == -1.0f);
  const float surround[6] = {0.3f, 0.6f, 0.9f, -0.75f, 0.0f, 0.0f};
  downmix_to_mono(surround, 2, 3, mono);
  CHECK(std::fabs(mono[0] - 0.6f) < 1e-6f && std::fabs(mono[1] + 0.25f) < 1e-6f);

  const std::int16_t pcm[6] = {16384, 0, -32768, -32768, 32767, -32768};
  downmix_to_mono(pcm, 3, 2, mono);
  CHECK(mono[0] == 0.25f && mono[1] == -1.0f && mono[2] == -0.5f / 32768);
  downmix_to_mono(pcm, 3, 1, mono);
  CHECK(mono[0] == 0.5f && mono[1] == 0.0f && mono[2] == -1.0f);
}

static void test_level_db() {
  CHECK(level_db(static_cast<const float*>(nullptr), 0) == -120);
  CHECK(level_db(static_cast<const std::int16_t*>(nullptr), 0) == -120);
  const std::vector<float> silence(480, 0.0f);
  const std::vector<std::int16_t> pcm_silence(480, 0);
  CHECK(level_db(silence.data(), silence.size()) == -120);
  CHECK(level_db(pcm_silence.data(), pcm_silence.size()) == -120);
  const float whisper[2] = {1e-9f, -1e-9f};  // -180 dBFS: floored
  CHECK(level_db(whisper, 2) == -120);

  std::vector<float> square(480);
  std::vector<std::int16_t> pcm_square(480);
  for (std::size_t i = 0; i < square.size(); i++) {
    square[i] = (i / 24) % 2 == 0 ? 1.0f : -1.0f;
    pcm_square[i] = static_cast<std::int16_t>((i / 24) % 2 == 0 ? 32767 : -32768);
  }
  CHECK(level_db(square.data(), square.size()) == 0);
  CHECK(std::fabs(level_db(pcm_square.data(), pcm_square.size())) < 0.001);
  for (std::size_t i = 0; i < square.size(); i++) {
    square[i] *= 0.5f;
    pcm_square[i] = static_cast<std::int16_t>(pcm_square[i] > 0 ? 16384 : -16384);
  }
  CHECK(std::fabs(level_db(square.data(), square.size()) + 6.0206) < 0.001);
  CHECK(std::fabs(level_db(pcm_square.data(), pcm_square.size()) + 6.0206) < 0.001);

  const std::vector<float> full_sine = sine(4800, 1000, 48000, 1.0);
  const std::vector<float> half_sine = sine(4800, 1000, 48000, 0.5);
  CHECK(std::fabs(level_db(full_sine.data(), full_sine.size()) + 3.0103) < 0.001);
  CHECK(std::fabs(level_db(half_sine.data(), half_sine.size()) + 9.0309) < 0.001);
  const std::int16_t lsb = 1;  // one LSB: 20·log10(1/32768)
  CHECK(std::fabs(level_db(&lsb, 1) + 90.309) < 0.001);
}

// ── Source mixer ──

static void test_mixer_passes_a_single_input_through() {
  SourceMixer mixer(1, 64, 0);
  CHECK(mixer.inputs() == 1);
  const float in[5] = {0.1f, -0.2f, 1.0f, -1.0f, 0.333f};
  std::vector<float> out = {9.0f};  // appended after what is there
  CHECK(mixer.push(0, in, 5) == 5);
  CHECK(mixer.mix(out) == 5);
  CHECK(out == std::vector<float>({9.0f, 0.1f, -0.2f, 1.0f, -1.0f, 0.333f}));
  CHECK(mixer.mix(out) == 0);
  CHECK(out.size() == 6);

  SourceMixer none(0, 64, 0);
  CHECK(none.mix(out) == 0);
  CHECK(none.dropped() == 0);
}

static void test_mixer_sums_and_clamps() {
  SourceMixer mixer(3, 64, 100);
  const float a[4] = {0.25f, 0.7f, -0.7f, 0.5f};
  const float b[4] = {0.5f, 0.6f, -0.6f, -0.5f};
  const float c[4] = {0.125f, 0.0f, 0.0f, 0.0f};
  mixer.push(0, a, 4);
  mixer.push(1, b, 4);
  mixer.push(2, c, 4);
  std::vector<float> out;
  CHECK(mixer.mix(out) == 4);
  CHECK(out == std::vector<float>({0.875f, 1.0f, -1.0f, 0.0f}));
}

static void test_mixer_waits_for_a_slower_input_within_max_lag() {
  SourceMixer mixer(2, 1000, 100);
  const std::vector<float> a(150, 0.25f);
  const std::vector<float> b(150, 0.5f);
  std::vector<float> out;
  // Input 1 has nothing yet, but input 0 is only 50 samples ahead: wait.
  mixer.push(0, a.data(), 50);
  CHECK(mixer.mix(out) == 0);
  // Both have some: mix what both have; input 0 keeps its extra 20.
  mixer.push(1, b.data(), 30);
  CHECK(mixer.mix(out) == 30);
  CHECK(out == std::vector<float>(30, 0.75f));
  mixer.push(1, b.data(), 20);
  CHECK(mixer.mix(out) == 20);
  CHECK(out.size() == 50 && out.back() == 0.75f);
  CHECK(mixer.mix(out) == 0);
}

static void test_mixer_treats_a_stalled_input_as_silence_beyond_max_lag() {
  SourceMixer mixer(2, 1000, 100);
  const std::vector<float> a(300, 0.25f);
  const std::vector<float> b(10, 0.5f);
  std::vector<float> out;
  mixer.push(0, a.data(), 60);
  CHECK(mixer.mix(out) == 0);
  mixer.push(0, a.data(), 50);  // 110 ahead of a silent input: stop waiting
  CHECK(mixer.mix(out) == 110);
  CHECK(out == std::vector<float>(110, 0.25f));
  // A laggard contributes what it has, then silence.
  out.clear();
  mixer.push(0, a.data(), 200);
  mixer.push(1, b.data(), 10);
  CHECK(mixer.mix(out) == 200);
  CHECK(out.size() == 200 && out[0] == 0.75f && out[9] == 0.75f && out[10] == 0.25f && out[199] == 0.25f);
  CHECK(mixer.mix(out) == 0);
}

static void test_mixer_counts_drops() {
  SourceMixer mixer(2, 8, 100);
  const float in[10] = {0.1f, 0.1f, 0.1f, 0.1f, 0.1f, 0.1f, 0.1f, 0.1f, 0.1f, 0.1f};
  CHECK(mixer.push(0, in, 10) == 8);
  CHECK(mixer.dropped() == 2);
  CHECK(mixer.push(1, in, 5) == 5);
  CHECK(mixer.dropped() == 2);
  CHECK(mixer.push(0, in, 3) == 0);
  CHECK(mixer.dropped() == 5);
  CHECK(mixer.push(2, in, 3) == 0);  // no such input
  std::vector<float> out;
  CHECK(mixer.mix(out) == 5);  // input 1 has 5, within max_lag of input 0's 8
  CHECK(mixer.push(1, in, 4) == 4);
  CHECK(mixer.mix(out) == 3);
  CHECK(mixer.push(0, in, 8) == 8);
  CHECK(mixer.dropped() == 5);
}

static void test_mixer_between_three_threads() {
  // Two capture threads and one engine thread, no locks: every sample of both is summed exactly once, in order.
  // Values are multiples of 2^-14, so the sums are exact; producers retry what did not fit (counted as dropped).
  const int total = 200'000;
  SourceMixer mixer(2, 512, 1'000'000);
  auto value = [](int input, int i) {
    return input == 0 ? static_cast<float>(i % 4096) / 8192 : -static_cast<float>((i * 7) % 4096) / 16384;
  };
  std::atomic<std::size_t> rejected{0};
  auto produce = [&](int input, int chunk) {
    std::vector<float> block(static_cast<std::size_t>(chunk));
    int sent = 0;
    while (sent < total) {
      const int want = std::min(chunk, total - sent);
      for (int i = 0; i < want; i++) block[static_cast<std::size_t>(i)] = value(input, sent + i);
      const std::size_t accepted =
          mixer.push(static_cast<std::size_t>(input), block.data(), static_cast<std::size_t>(want));
      rejected += static_cast<std::size_t>(want) - accepted;
      sent += static_cast<int>(accepted);
      if (accepted == 0) std::this_thread::yield();
    }
  };
  std::thread first(produce, 0, 61);
  std::thread second(produce, 1, 97);
  std::vector<float> out;
  out.reserve(total);
  while (out.size() < static_cast<std::size_t>(total))
    if (mixer.mix(out) == 0) std::this_thread::yield();
  first.join();
  second.join();
  CHECK(out.size() == static_cast<std::size_t>(total));
  bool in_order = true;
  for (int i = 0; i < total; i++) in_order = in_order && out[static_cast<std::size_t>(i)] == value(0, i) + value(1, i);
  CHECK(in_order);
  CHECK(mixer.mix(out) == 0);
  CHECK(mixer.dropped() == rejected.load());
}

int main() {
  test_equal_rates_pass_through_exactly();
  test_length_follows_the_rate_ratio();
  test_chunked_conversion_matches_one_shot();
  test_a_tone_keeps_its_level_and_frequency();
  test_downsampling_rejects_what_would_alias();
  test_an_impulse_stays_in_place();
  test_finish_keeps_the_end_of_the_stream();
  test_finish_and_reset_start_a_new_stream();
  test_int16_input_is_scaled();
  test_sample_conversions_round_and_clamp();
  test_downmix_takes_the_mean_of_the_channels();
  test_level_db();
  test_mixer_passes_a_single_input_through();
  test_mixer_sums_and_clamps();
  test_mixer_waits_for_a_slower_input_within_max_lag();
  test_mixer_treats_a_stalled_input_as_silence_beyond_max_lag();
  test_mixer_counts_drops();
  test_mixer_between_three_threads();
  return livebridge_test::finish();
}
