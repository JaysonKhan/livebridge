// Binary audio frame v1 — must stay byte-identical to packages/protocol/src/frame.ts and the Swift FrameCodec.
// All three codecs are tested against packages/protocol/fixtures/frames.json.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>
#include <vector>

namespace livebridge {

struct AudioFrame {
  enum class Kind : std::uint8_t { capture = 1, synthesized = 2 };
  enum class Direction : std::uint8_t { out = 0, in = 1 };

  static constexpr std::uint8_t kVersion = 1;
  static constexpr std::size_t kHeaderBytes = 28;
  static constexpr std::size_t kMaxPayloadBytes = 192'000;
  static constexpr std::uint8_t kFlagEndOfTurn = 0x01;

  Kind kind = Kind::capture;
  Direction direction = Direction::out;
  std::uint8_t flags = 0;
  std::uint32_t generation = 0;
  std::uint32_t sequence = 0;
  std::uint64_t timestamp_us = 0;
  std::uint32_t turn_id = 0;
  /// PCM s16le mono; always a whole number of samples.
  std::vector<std::uint8_t> payload;

  bool is_end_of_turn() const { return (flags & kFlagEndOfTurn) != 0; }
};

enum class FrameError {
  none,
  too_short,
  bad_version,
  bad_kind,
  bad_direction,
  bad_flags,
  length_mismatch,
  payload_too_large,
  odd_payload,
};

/// The wire name of an error ("too_short", ...), the same string the other codecs report.
const char* frame_error_code(FrameError error);

const char* direction_name(AudioFrame::Direction direction);
bool direction_from_name(std::string_view name, AudioFrame::Direction& direction);

/// Both return FrameError::none on success and leave `out` unspecified otherwise. Neither throws.
FrameError encode_frame(const AudioFrame& frame, std::vector<std::uint8_t>& out);
FrameError decode_frame(const std::uint8_t* data, std::size_t size, AudioFrame& out);

}  // namespace livebridge
