#include "livebridge/frame_codec.h"

namespace livebridge {
namespace {

template <typename T>
void append_big_endian(T value, std::vector<std::uint8_t>& out) {
  for (int shift = static_cast<int>(sizeof(T)) * 8 - 8; shift >= 0; shift -= 8)
    out.push_back(static_cast<std::uint8_t>(value >> shift));
}

template <typename T>
T read_big_endian(const std::uint8_t* bytes) {
  T value = 0;
  for (std::size_t i = 0; i < sizeof(T); i++) value = static_cast<T>((value << 8) | bytes[i]);
  return value;
}

}  // namespace

const char* frame_error_code(FrameError error) {
  switch (error) {
    case FrameError::none: return "none";
    case FrameError::too_short: return "too_short";
    case FrameError::bad_version: return "bad_version";
    case FrameError::bad_kind: return "bad_kind";
    case FrameError::bad_direction: return "bad_direction";
    case FrameError::bad_flags: return "bad_flags";
    case FrameError::length_mismatch: return "length_mismatch";
    case FrameError::payload_too_large: return "payload_too_large";
    case FrameError::odd_payload: return "odd_payload";
  }
  return "unknown";
}

const char* direction_name(AudioFrame::Direction direction) {
  return direction == AudioFrame::Direction::out ? "out" : "in";
}

bool direction_from_name(std::string_view name, AudioFrame::Direction& direction) {
  if (name == "out") direction = AudioFrame::Direction::out;
  else if (name == "in") direction = AudioFrame::Direction::in;
  else return false;
  return true;
}

FrameError encode_frame(const AudioFrame& frame, std::vector<std::uint8_t>& out) {
  if (frame.payload.size() > AudioFrame::kMaxPayloadBytes) return FrameError::payload_too_large;
  if (frame.payload.size() % 2 != 0) return FrameError::odd_payload;
  if ((frame.flags & ~AudioFrame::kFlagEndOfTurn) != 0) return FrameError::bad_flags;
  out.clear();
  out.reserve(AudioFrame::kHeaderBytes + frame.payload.size());
  out.push_back(AudioFrame::kVersion);
  out.push_back(static_cast<std::uint8_t>(frame.kind));
  out.push_back(static_cast<std::uint8_t>(frame.direction));
  out.push_back(frame.flags);
  append_big_endian(frame.generation, out);
  append_big_endian(frame.sequence, out);
  append_big_endian(frame.timestamp_us, out);
  append_big_endian(frame.turn_id, out);
  append_big_endian(static_cast<std::uint32_t>(frame.payload.size()), out);
  out.insert(out.end(), frame.payload.begin(), frame.payload.end());
  return FrameError::none;
}

FrameError decode_frame(const std::uint8_t* data, std::size_t size, AudioFrame& out) {
  if (size < AudioFrame::kHeaderBytes) return FrameError::too_short;
  if (data[0] != AudioFrame::kVersion) return FrameError::bad_version;
  if (data[1] != 1 && data[1] != 2) return FrameError::bad_kind;
  if (data[2] > 1) return FrameError::bad_direction;
  if ((data[3] & ~AudioFrame::kFlagEndOfTurn) != 0) return FrameError::bad_flags;
  const std::size_t payload = read_big_endian<std::uint32_t>(data + 24);
  if (payload > AudioFrame::kMaxPayloadBytes) return FrameError::payload_too_large;
  if (payload != size - AudioFrame::kHeaderBytes) return FrameError::length_mismatch;
  if (payload % 2 != 0) return FrameError::odd_payload;
  out.kind = static_cast<AudioFrame::Kind>(data[1]);
  out.direction = static_cast<AudioFrame::Direction>(data[2]);
  out.flags = data[3];
  out.generation = read_big_endian<std::uint32_t>(data + 4);
  out.sequence = read_big_endian<std::uint32_t>(data + 8);
  out.timestamp_us = read_big_endian<std::uint64_t>(data + 12);
  out.turn_id = read_big_endian<std::uint32_t>(data + 20);
  out.payload.assign(data + AudioFrame::kHeaderBytes, data + size);
  return FrameError::none;
}

}  // namespace livebridge
