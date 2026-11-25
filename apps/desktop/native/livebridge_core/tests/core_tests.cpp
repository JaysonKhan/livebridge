// Tests of the frame codec, ring buffer and JSON module.
// Usage: core_tests <path to packages/protocol/fixtures/frames.json>
#include <atomic>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "check.h"
#include "livebridge/frame_codec.h"
#include "livebridge/json.h"
#include "livebridge/ring_buffer.h"

using namespace livebridge;

static std::vector<std::uint8_t> from_hex(const std::string& hex) {
  std::vector<std::uint8_t> bytes;
  for (std::size_t i = 0; i + 1 < hex.size(); i += 2)
    bytes.push_back(static_cast<std::uint8_t>(std::stoul(hex.substr(i, 2), nullptr, 16)));
  return bytes;
}

static Json parse(const std::string& text) {
  Json value;
  std::string error;
  if (!Json::parse(text, value, &error)) {
    livebridge_test::failures++;
    std::printf("FAILED to parse %s: %s\n", text.c_str(), error.c_str());
  }
  return value;
}

// ── Frame codec against the fixtures shared with the TypeScript and Swift codecs ──

static void test_shared_frame_fixtures(const std::string& path) {
  std::ifstream file(path);
  std::stringstream text;
  text << file.rdbuf();
  const Json fixtures = parse(text.str());
  const Json* valid = fixtures.find("valid");
  const Json* invalid = fixtures.find("invalid");
  CHECK(valid && valid->as_array().size() == 4);
  CHECK(invalid && invalid->as_array().size() == 9);
  if (!valid || !invalid) return;

  for (const Json& fixture : valid->as_array()) {
    const auto bytes = from_hex(fixture.find("hex")->as_string());
    AudioFrame frame;
    CHECK(decode_frame(bytes.data(), bytes.size(), frame) == FrameError::none);
    CHECK((frame.kind == AudioFrame::Kind::capture ? "capture" : "synthesized") == fixture.find("kind")->as_string());
    CHECK(direction_name(frame.direction) == fixture.find("direction")->as_string());
    CHECK(frame.flags == fixture.find("flags")->as_int());
    CHECK(frame.generation == static_cast<std::uint32_t>(fixture.find("generation")->as_int()));
    CHECK(frame.sequence == static_cast<std::uint32_t>(fixture.find("sequence")->as_int()));
    // The timestamp is a decimal string in the fixtures: it does not fit a JSON number.
    CHECK(std::to_string(frame.timestamp_us) == fixture.find("timestampUs")->as_string());
    CHECK(frame.turn_id == static_cast<std::uint32_t>(fixture.find("turnId")->as_int()));
    CHECK(frame.payload == from_hex(fixture.find("payloadHex")->as_string()));
    std::vector<std::uint8_t> encoded;
    CHECK(encode_frame(frame, encoded) == FrameError::none);
    CHECK(encoded == bytes);
  }
  for (const Json& fixture : invalid->as_array()) {
    const auto bytes = from_hex(fixture.find("hex")->as_string());
    AudioFrame frame;
    CHECK(frame_error_code(decode_frame(bytes.data(), bytes.size(), frame)) == fixture.find("error")->as_string());
  }
}

static void test_encode_refuses_bad_frames() {
  AudioFrame frame;
  std::vector<std::uint8_t> out;
  frame.payload.assign(AudioFrame::kMaxPayloadBytes + 2, 0);
  CHECK(encode_frame(frame, out) == FrameError::payload_too_large);
  frame.payload.assign(3, 0);
  CHECK(encode_frame(frame, out) == FrameError::odd_payload);
  frame.payload.assign(4, 0);
  frame.flags = 0x02;
  CHECK(encode_frame(frame, out) == FrameError::bad_flags);
  frame.flags = AudioFrame::kFlagEndOfTurn;
  CHECK(encode_frame(frame, out) == FrameError::none);
  CHECK(out.size() == AudioFrame::kHeaderBytes + 4);

  AudioFrame::Direction direction = AudioFrame::Direction::out;
  CHECK(direction_from_name("in", direction) && direction == AudioFrame::Direction::in);
  CHECK(!direction_from_name("sideways", direction));
}

// ── Ring buffer ──

static void test_ring_buffer_wraps_overflows_and_flushes() {
  RingBuffer ring(8);
  const float in[6] = {1, 2, 3, 4, 5, 6};
  float out[8] = {};
  CHECK(ring.write(in, 6) == 6);
  CHECK(ring.available_to_read() == 6);
  CHECK(ring.read(out, 4) == 4);
  CHECK(out[0] == 1 && out[3] == 4);
  // Wraps around the end of the storage; only what fits is accepted.
  CHECK(ring.write(in, 6) == 6);
  CHECK(ring.write(in, 6) == 0);
  CHECK(ring.read(out, 8) == 8);
  CHECK(out[0] == 5 && out[1] == 6 && out[2] == 1 && out[7] == 6);
  CHECK(ring.read(out, 8) == 0);
  // Flush drops everything queued without the consumer taking part.
  CHECK(ring.write(in, 6) == 6);
  ring.flush();
  CHECK(ring.available_to_read() == 0);
  CHECK(ring.read(out, 8) == 0);
  CHECK(ring.write(in, 6) == 6);
  CHECK(ring.read(out, 8) == 6);
  CHECK(ring.written() == 24 && ring.consumed() == 24);
}

static void test_ring_buffer_between_two_threads() {
  // One producer and one consumer, no locks: every sample arrives once and in order.
  const int total = 200'000;
  RingBuffer ring(1024);
  std::atomic<bool> in_order{true};
  std::thread consumer([&] {
    float block[97];
    int next = 0;
    while (next < total) {
      const std::size_t n = ring.read(block, 97);
      for (std::size_t i = 0; i < n; i++, next++)
        if (block[i] != static_cast<float>(next)) in_order = false;
      if (n == 0) std::this_thread::yield();
    }
  });
  float block[61];
  int sent = 0;
  while (sent < total) {
    const int want = std::min(61, total - sent);
    for (int i = 0; i < want; i++) block[i] = static_cast<float>(sent + i);
    const std::size_t n = ring.write(block, static_cast<std::size_t>(want));
    sent += static_cast<int>(n);
    if (n == 0) std::this_thread::yield();
  }
  consumer.join();
  CHECK(in_order.load());
  CHECK(ring.available_to_read() == 0);
}

// ── JSON ──

static void test_json_reads_and_writes_protocol_messages() {
  const Json message = parse(R"({"v":1,"type":"caption.final","direction":"out","turn_id":7,"text":"Salom \"dunyo\"\n","ok":true,"gap":null,"list":[1,2.5,-3e2]})");
  CHECK(message.find("v")->as_int() == 1);
  CHECK(message.find("type")->as_string() == "caption.final");
  CHECK(message.find("text")->as_string() == "Salom \"dunyo\"\n");
  CHECK(message.find("ok")->as_bool());
  CHECK(message.find("gap")->is_null());
  CHECK(message.find("list")->as_array().size() == 3);
  CHECK(message.find("list")->as_array()[2].as_number() == -300);
  CHECK(message.find("missing") == nullptr);
  CHECK(message.find("v")->find("nested") == nullptr);
  // Text survives a write and a second read unchanged; integers have no fraction.
  CHECK(parse(message.dump()) == message);
  CHECK(Json(4294967295ULL).dump() == "4294967295");
  CHECK(Json(1.5).dump() == "1.5");

  Json built;
  built.set("type", "session.configure");
  built.set("generation", 3);
  built.set("type", "ping");
  CHECK(built.dump() == R"({"type":"ping","generation":3})");
}

static void test_json_handles_unicode_and_escapes() {
  // A \u escape, a surrogate pair, and raw UTF-8 all end up as UTF-8.
  const Json text = parse(R"(["o\u02bbzbek","\ud83d\ude00","Ўзбек"])");
  CHECK(text.as_array()[0].as_string() == "o\xCA\xBBzbek");
  CHECK(text.as_array()[1].as_string() == "\xF0\x9F\x98\x80");
  CHECK(text.as_array()[2].as_string() == "\xD0\x8E\xD0\xB7\xD0\xB1\xD0\xB5\xD0\xBA");
  CHECK(Json(std::string("tab\there\x01")).dump() == R"("tab\there\u0001")");
  CHECK(parse(text.dump()) == text);
}

static void test_json_rejects_malformed_input() {
  Json value;
  std::string error;
  for (const char* bad : {"", "{", "[1,]", "{\"a\":}", "{'a':1}", "01", "1.", "tru", "\"unterminated", "\"\\x\"",
                          "\"\\ud83d\"", "[1] trailing", "{\"a\":1,}", "nan"}) {
    CHECK(!Json::parse(bad, value, &error));
  }
  CHECK(!error.empty());
  // Hostile nesting is refused instead of overflowing the stack.
  CHECK(!Json::parse(std::string(100'000, '['), value));
  CHECK(Json::parse(" \n[ ] ", value) && value.is_array());
}

int main(int argc, char** argv) {
  if (argc < 2) {
    std::printf("usage: core_tests <frames.json>\n");
    return 2;
  }
  test_shared_frame_fixtures(argv[1]);
  test_encode_refuses_bad_frames();
  test_ring_buffer_wraps_overflows_and_flushes();
  test_ring_buffer_between_two_threads();
  test_json_reads_and_writes_protocol_messages();
  test_json_handles_unicode_and_escapes();
  test_json_rejects_malformed_input();
  return livebridge_test::finish();
}
