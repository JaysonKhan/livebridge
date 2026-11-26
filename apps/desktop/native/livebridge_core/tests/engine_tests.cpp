// Tests of the session engine against a fake platform: every host call is recorded, the test feeds the gateway's
// messages and the captured audio, and the clock only moves when the test moves it.
#include <algorithm>
#include <cstdio>
#include <functional>
#include <initializer_list>
#include <map>
#include <string>
#include <utility>
#include <vector>

#include "check.h"
#include "livebridge/engine.h"

using namespace livebridge;

static const Direction kOut = Direction::out;
static const Direction kIn = Direction::in;
/// One capture frame: 20 ms of 16 kHz mono s16le.
static const std::size_t kFrame = 640;

// ── JSON helpers ──

static const Json& at(const Json& json, std::initializer_list<const char*> path) {
  static const Json missing;
  const Json* node = &json;
  for (const char* key : path) {
    node = node->find(key);
    if (!node) return missing;
  }
  return *node;
}

static std::string str(const Json& json, const char* key) { return at(json, {key}).as_string(); }
static long long num(const Json& json, const char* key) { return at(json, {key}).as_int(-1); }
static bool yes(const Json& json, const char* key) { return at(json, {key}).as_bool(); }
static bool has(const Json& json, const char* key) { return json.find(key) != nullptr; }

/// Objects with their members sorted, so that two messages compare equal whatever order they were built in.
static Json canonical(const Json& value) {
  if (value.is_array()) {
    Json::Array items;
    for (const Json& item : value.as_array()) items.push_back(canonical(item));
    return Json(std::move(items));
  }
  if (value.is_object()) {
    Json::Object members;
    for (const auto& member : value.as_object()) members.emplace_back(member.first, canonical(member.second));
    std::sort(members.begin(), members.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
    return Json(std::move(members));
  }
  return value;
}

/// True when `actual` is exactly the JSON in `expected`: the same members, no more and no fewer.
static bool same(const Json& actual, const char* expected) {
  Json parsed;
  if (Json::parse(expected, parsed) && canonical(actual) == canonical(parsed)) return true;
  std::printf("  expected %s\n  actual   %s\n", expected, actual.dump().c_str());
  return false;
}

/// The byte at position `index` of the endless test recording that `Session::mic` and `Session::source` play.
static std::uint8_t recorded(std::size_t index) { return static_cast<std::uint8_t>(index % 251); }

// ── The fake platform ──

class FakeHost : public EngineHost {
 public:
  struct Sink {
    bool open = false;
    std::string uid;
    bool muted = false;
    /// Refuse the next writes, as a full queue does.
    bool full = false;
    std::int64_t written = 0;
    std::int64_t consumed = 0;
    int flushes = 0;
    int end_inputs = 0;
    /// Each accepted write as (bytes, sample rate), and all accepted bytes in order.
    std::vector<std::pair<std::size_t, int>> writes;
    std::vector<std::uint8_t> audio;
  };

  FakeHost() {
    devices["mic"] = {1, 0, false};
    devices["phones"] = {0, 2, false};
    devices["cable"] = {0, 2, true};
  }

  std::uint64_t now = 5'000'000'000ULL;
  std::map<std::string, DeviceInfo> devices;
  /// Every call that changes something, in order.
  std::vector<std::string> log;

  bool connected = false;
  int connects = 0;
  int closes = 0;
  std::string gateway_url;
  /// The session request of the last `connect`.
  SessionRequest request;
  std::vector<Json> sent;
  std::vector<AudioFrame> frames;
  bool network_keeps_up = true;

  bool mic_open = false;
  std::string mic_uid;
  bool source_open = false;
  std::vector<int> source_pids;
  bool source_is_alive = true;
  int source_alive_calls = 0;
  /// Make the matching open call fail; a non-empty code is reported as the reason.
  bool mic_fails = false;
  bool source_fails = false;
  bool sink_fails[2] = {false, false};
  HostError failure;
  Sink sinks[2];

  bool nothing_open() const { return !mic_open && !source_open && !sinks[0].open && !sinks[1].open; }

  std::uint64_t now_us() override { return now; }

  void connect(const std::string& url, const SessionRequest& session_request) override {
    CHECK(!connected);  // one connection at a time
    connected = true;
    connects++;
    gateway_url = url;
    request = session_request;
    log.push_back("connect");
  }

  void send_text(const std::string& json) override {
    CHECK(connected);
    Json message;
    CHECK(Json::parse(json, message) && message.is_object());
    CHECK(num(message, "v") == 1);  // every protocol message carries its version
    log.push_back(str(message, "type"));
    sent.push_back(std::move(message));
  }

  bool send_binary(const std::uint8_t* data, std::size_t size) override {
    CHECK(connected);
    if (!network_keeps_up) return false;
    AudioFrame frame;
    CHECK(decode_frame(data, size, frame) == FrameError::none);
    log.push_back(std::string("frame:") + direction_name(frame.direction));
    frames.push_back(std::move(frame));
    return true;
  }

  void close() override {
    CHECK(connected);  // exactly one close per connect
    connected = false;
    closes++;
    log.push_back("close");
  }

  bool find_device(const std::string& uid, DeviceInfo& info) override {
    const auto found = devices.find(uid);
    if (found == devices.end()) return false;
    info = found->second;
    return true;
  }

  bool open_microphone(const std::string& uid, HostError& error) override {
    if (mic_fails) return fail(error);
    CHECK(!mic_open);
    mic_open = true;
    mic_uid = uid;
    log.push_back("open_mic");
    return true;
  }

  void close_microphone() override {
    CHECK(mic_open);
    mic_open = false;
    log.push_back("close_mic");
  }

  bool open_source(const std::vector<int>& pids, HostError& error) override {
    if (source_fails) return fail(error);
    CHECK(!source_open);
    source_open = true;
    source_pids = pids;
    log.push_back("open_source");
    return true;
  }

  void close_source() override {
    CHECK(source_open);
    source_open = false;
    log.push_back("close_source");
  }

  bool source_alive() override {
    source_alive_calls++;
    return source_is_alive;
  }

  bool open_sink(Direction direction, const std::string& uid, HostError& error) override {
    if (sink_fails[index(direction)]) return fail(error);
    CHECK(!sinks[index(direction)].open);
    sinks[index(direction)] = Sink{};
    sinks[index(direction)].open = true;
    sinks[index(direction)].uid = uid;
    log.push_back(std::string("open_sink:") + direction_name(direction));
    return true;
  }

  void close_sink(Direction direction) override {
    CHECK(sinks[index(direction)].open);
    sinks[index(direction)].open = false;
    log.push_back(std::string("close_sink:") + direction_name(direction));
  }

  bool sink_write(Direction direction, const std::uint8_t* pcm, std::size_t bytes, int sample_rate) override {
    Sink& sink = sinks[index(direction)];
    CHECK(sink.open);
    if (sink.full) return false;
    sink.writes.emplace_back(bytes, sample_rate);
    sink.audio.insert(sink.audio.end(), pcm, pcm + bytes);
    sink.written += static_cast<std::int64_t>(bytes / 2);
    return true;
  }

  void sink_end_input(Direction direction) override {
    CHECK(sinks[index(direction)].open);
    sinks[index(direction)].end_inputs++;
  }

  void sink_flush(Direction direction) override {
    Sink& sink = sinks[index(direction)];
    CHECK(sink.open);
    sink.consumed = sink.written;
    sink.flushes++;
    log.push_back(std::string("flush:") + direction_name(direction));
  }

  void sink_set_muted(Direction direction, bool muted) override {
    CHECK(sinks[index(direction)].open);
    sinks[index(direction)].muted = muted;
    log.push_back(std::string(muted ? "mute:" : "unmute:") + direction_name(direction));
  }

  std::int64_t sink_written(Direction direction) override { return sinks[index(direction)].written; }
  std::int64_t sink_consumed(Direction direction) override { return sinks[index(direction)].consumed; }

 private:
  static std::size_t index(Direction direction) { return direction == kOut ? 0 : 1; }

  bool fail(HostError& error) {
    if (!failure.code.empty()) error = failure;
    return false;
  }
};

/// One engine on one fake host, with what the tests do to it most.
struct Session {
  FakeHost host;
  std::vector<Json> events;
  Engine engine{host, [this](const Json& event) { events.push_back(event); }};
  std::size_t mic_fed = 0;
  std::size_t source_fed = 0;

  /// Forgets what was recorded so far, so that the next checks see only what happens next.
  void forget() {
    events.clear();
    host.sent.clear();
    host.frames.clear();
    host.log.clear();
  }

  void text(const std::string& json) { engine.on_transport_text(json); }

  /// The gateway's `session.ready`. A direction that is not ready here is reported as not enabled either, except
  /// `out`, which every session has.
  void ready(bool out_ready, bool in_ready, int out_rate = 24'000, int in_rate = 24'000, bool mock = false) {
    const auto word = [](bool value) { return value ? "true" : "false"; };
    char message[600];
    std::snprintf(message, sizeof(message),
                  R"({"v":1,"type":"session.ready","session_id":"s1","max_session_seconds":3600,)"
                  R"("providers":{"stt":"a","translation":"b","tts":"c","mock":%s},)"
                  R"("directions":{"out":{"enabled":true,"ready":%s,"speak":true,"synth_sample_rate":%d},)"
                  R"("in":{"enabled":%s,"ready":%s,"speak":true,"synth_sample_rate":%d}}})",
                  word(mock), word(out_ready), out_rate, word(in_ready), word(in_ready), in_rate);
    text(message);
  }

  /// Start, connect and get ready; then forget all of it.
  void go(const Json& map) {
    CHECK(engine.start(map));
    engine.on_transport_open();
    ready(true, !at(map, {"sourcePids"}).as_array().empty());
    forget();
  }

  /// A caption of the given kind ("caption.final", ...) from the gateway.
  void caption(const char* type, const char* direction, int turn, int generation, const char* words = "x") {
    char message[300];
    std::snprintf(message, sizeof(message),
                  R"({"v":1,"type":"%s","direction":"%s","turn_id":%d,"generation":%d,"text":"%s"})", type, direction,
                  turn, generation, words);
    text(message);
  }

  /// A frame of synthesized speech from the gateway, `last` being the turn's END_OF_TURN frame; every payload byte
  /// is the turn id.
  void synthesized(Direction direction, std::uint32_t generation, std::uint32_t turn, std::size_t bytes, bool last) {
    AudioFrame frame;
    frame.kind = AudioFrame::Kind::synthesized;
    frame.direction = direction;
    frame.flags = last ? AudioFrame::kFlagEndOfTurn : 0;
    frame.generation = generation;
    frame.turn_id = turn;
    frame.payload.assign(bytes, static_cast<std::uint8_t>(turn));
    std::vector<std::uint8_t> encoded;
    CHECK(encode_frame(frame, encoded) == FrameError::none);
    engine.on_transport_binary(encoded.data(), encoded.size());
  }

  /// The next `bytes` of the test recording, captured from the microphone / from the meeting app.
  void mic(std::size_t bytes) { capture(kOut, mic_fed, bytes); }
  void source(std::size_t bytes) { capture(kIn, source_fed, bytes); }

 private:
  void capture(Direction direction, std::size_t& fed, std::size_t bytes) {
    std::vector<std::uint8_t> pcm(bytes);
    for (std::size_t i = 0; i < bytes; i++) pcm[i] = recorded(fed + i);
    fed += bytes;
    engine.on_captured(direction, pcm.data(), pcm.size());
  }
};

/// A valid `start` map: Uzbek owner, English call, every device of the fake host, two meeting processes.
static Json settings(const char* mode, const char* commit, bool with_source = true) {
  Json map;
  map.set("gatewayUrl", "https://bridge.example.com");
  map.set("accessToken", "secret-token");
  map.set("micUid", "mic");
  map.set("headphonesUid", "phones");
  map.set("virtualMicUid", "cable");
  map.set("sourcePids", with_source ? Json::Array{Json(4242), Json(4243)} : Json::Array{});
  map.set("targetLang", "en");
  map.set("mode", mode);
  map.set("outCommit", commit);
  return map;
}

/// `map` without its member `key`.
static Json without(const Json& map, const char* key) {
  Json::Object members;
  for (const auto& member : map.as_object()) {
    if (member.first != key) members.push_back(member);
  }
  return Json(std::move(members));
}

/// `settings()` for a connection mode. `keys` drops the access token and carries both provider keys.
static Json connected_by(const char* connection, const char* mode = "captions", const char* commit = "manual") {
  Json map = settings(mode, commit);
  map.set("connection", connection);
  if (std::string(connection) == "keys") {
    map = without(map, "accessToken");
    map.set("elevenlabsApiKey", "el-key");
    map.set("geminiApiKey", "gm-key");
  }
  return map;
}

static bool logged(const FakeHost& host, std::initializer_list<const char*> expected) {
  if (std::equal(host.log.begin(), host.log.end(), expected.begin(), expected.end())) return true;
  std::printf("  host calls were:");
  for (const std::string& call : host.log) std::printf(" %s", call.c_str());
  std::printf("\n");
  return false;
}

static const char* const kIdleState =
    R"({"type":"state","state":"idle","outReady":false,"inReady":false,"capturing":false,"mock":false,)"
    R"("bypass":false,"outgoingMuted":false,"incomingAudioMuted":false})";

// ── Settings ──

static void test_settings_are_validated() {
  EngineConfig config;
  CHECK(EngineConfig::parse(settings("incoming", "manual"), config));
  CHECK(config.gateway_url == "https://bridge.example.com" && config.access_token == "secret-token");
  CHECK(config.mic_uid == "mic" && config.headphones_uid == "phones");
  CHECK(config.virtual_mic_uid && *config.virtual_mic_uid == "cable");
  CHECK(config.source_pids == std::vector<int>({4242, 4243}));
  CHECK(config.my_lang == "uz" && config.target_lang == "en");  // the owner's language defaults to Uzbek
  CHECK(config.mode == EngineConfig::Mode::incoming && config.out_commit == "manual");
  CHECK(config.translation_model.empty());
  CHECK(config.out_voice_id.empty() && config.in_voice_id.empty());

  Json other = settings("bidirectional", "turn_prediction");
  other.set("gatewayUrl", "http://127.0.0.1:8201");
  other.set("myLang", "de");
  other.set("targetLang", "fil");
  other.set("virtualMicUid", Json());
  other.set("translationModel", "fast-1");
  other.set("sourcePids", Json::Array{Json(7), Json("eight"), Json(-1)});
  CHECK(EngineConfig::parse(other, config));
  CHECK(config.gateway_url == "http://127.0.0.1:8201" && config.my_lang == "de" && config.target_lang == "fil");
  CHECK(!config.virtual_mic_uid && config.translation_model == "fast-1");
  CHECK(config.mode == EngineConfig::Mode::bidirectional && config.out_commit == "turn_prediction");
  CHECK(config.source_pids == std::vector<int>({7}));

  const auto refused = [](const char* key, Json value) {
    Json bad = settings("incoming", "manual");
    bad.set(key, std::move(value));
    EngineConfig ignored;
    return !EngineConfig::parse(bad, ignored);
  };
  CHECK(refused("gatewayUrl", "ftp://bridge.example.com"));
  CHECK(refused("gatewayUrl", "bridge.example.com"));
  CHECK(refused("gatewayUrl", "https://"));
  CHECK(refused("gatewayUrl", 5));
  CHECK(refused("accessToken", ""));
  CHECK(refused("micUid", Json()));
  CHECK(refused("headphonesUid", 1));
  CHECK(refused("targetLang", "EN"));
  CHECK(refused("targetLang", "english"));
  CHECK(refused("targetLang", "e"));
  CHECK(refused("targetLang", Json()));
  CHECK(refused("targetLang", "uz"));  // the same as the default owner's language
  CHECK(refused("myLang", "en"));      // the same as the call's language
  CHECK(refused("myLang", "u2"));
  CHECK(refused("mode", "everything"));
  CHECK(refused("outCommit", "auto"));
  CHECK(!EngineConfig::parse(Json("not a map"), config));
  CHECK(!EngineConfig::parse(Json(), config));
  CHECK(config.my_lang == "de");  // a refused map leaves the result untouched

  // Voice ids: a well-formed one is kept; anything else counts as "not chosen" and never refuses the start.
  const auto voices = [](Json out, Json in) {
    Json map = settings("bidirectional", "manual");
    map.set("outVoiceId", std::move(out));
    map.set("inVoiceId", std::move(in));
    EngineConfig parsed;
    CHECK(EngineConfig::parse(map, parsed));
    return parsed.out_voice_id + "|" + parsed.in_voice_id;
  };
  CHECK(voices("voiceChosenOut01", "voiceChosenIn001") == "voiceChosenOut01|voiceChosenIn001");
  CHECK(voices("ehTFHBkERkWR22A3sR8M", Json()) == "ehTFHBkERkWR22A3sR8M|");
  CHECK(voices("", "bad id") == "|");
  CHECK(voices("short", std::string(41, 'a')) == "|");                      // 10 to 40 characters
  CHECK(voices(std::string(10, 'a'), std::string(40, 'Z')) == std::string(10, 'a') + "|" + std::string(40, 'Z'));
  CHECK(voices("../../etc/passwd", 5) == "|");
  CHECK(voices("voiceChosenOut01\n", "voiceChosenIn001 ") == "|");

  // The engine refuses such a map outright: no event, no device, no connection.
  Session s;
  Json bad = settings("incoming", "manual");
  bad.set("mode", "everything");
  CHECK(!s.engine.start(bad));
  CHECK(s.events.empty() && s.host.log.empty());
}

// ── Connection modes ──

static void test_connection_modes_are_validated() {
  using Connection = EngineConfig::Connection;
  EngineConfig config;
  CHECK(EngineConfig::parse(settings("captions", "manual"), config));
  CHECK(config.connection == Connection::token);  // absent: the user's own gateway and its static token
  CHECK(EngineConfig::parse(connected_by("token"), config) && config.connection == Connection::token);
  CHECK(EngineConfig::parse(connected_by("account"), config) && config.connection == Connection::account);
  CHECK(config.access_token == "secret-token");

  // Keys mode needs both provider keys and no access token at all.
  CHECK(EngineConfig::parse(connected_by("keys"), config));
  CHECK(config.connection == Connection::keys && config.access_token.empty());
  CHECK(config.elevenlabs_api_key == "el-key" && config.gemini_api_key == "gm-key");
  Json keys = connected_by("keys");
  keys.set("accessToken", "");
  CHECK(EngineConfig::parse(keys, config) && config.connection == Connection::keys);

  const auto refused = [](Json map) {
    EngineConfig ignored;
    return !EngineConfig::parse(map, ignored);
  };
  CHECK(refused(without(connected_by("keys"), "elevenlabsApiKey")));
  CHECK(refused(without(connected_by("keys"), "geminiApiKey")));
  keys = connected_by("keys");
  keys.set("elevenlabsApiKey", "");
  CHECK(refused(keys));
  keys = connected_by("keys");
  keys.set("geminiApiKey", 5);
  CHECK(refused(keys));
  // The other two modes need the access token.
  CHECK(refused(without(connected_by("token"), "accessToken")));
  CHECK(refused(without(connected_by("account"), "accessToken")));
  Json account = connected_by("account");
  account.set("accessToken", "");
  CHECK(refused(account));
  // Only the three modes; a present value must be one of them.
  for (Json unknown : {Json("cloud"), Json("Account"), Json(3), Json(), Json(true)}) {
    Json map = settings("captions", "manual");
    map.set("connection", std::move(unknown));
    CHECK(refused(map));
  }
  // A refused map leaves the result of the last accepted one untouched.
  CHECK(!EngineConfig::parse(account, config));
  CHECK(config.connection == Connection::keys && config.access_token.empty());
  CHECK(config.elevenlabs_api_key == "el-key" && config.gemini_api_key == "gm-key");

  Session s;
  CHECK(!s.engine.start(without(connected_by("keys"), "geminiApiKey")));
  CHECK(s.events.empty() && s.host.log.empty());
}

static void test_session_request_per_connection_mode() {
  const auto request_for = [](const Json& map) {
    EngineConfig config;
    CHECK(EngineConfig::parse(map, config));
    return session_request(config);
  };
  const auto body = [](const SessionRequest& request) {
    Json parsed;
    CHECK(Json::parse(request.body, parsed));
    return parsed;
  };

  // Token: exactly today's request — the static token and no body.
  const SessionRequest token = request_for(connected_by("token"));
  CHECK(token.bearer == "secret-token" && token.body.empty());
  CHECK(request_for(settings("captions", "manual")).bearer == "secret-token");

  // Account: the short-lived access token and the mode.
  const SessionRequest account = request_for(connected_by("account"));
  CHECK(account.bearer == "secret-token");
  CHECK(same(body(account), R"({"mode":"account"})"));

  // Keys: the user's own provider keys in the body and no Authorization.
  const SessionRequest keys = request_for(connected_by("keys"));
  CHECK(keys.bearer.empty());
  CHECK(same(body(keys), R"({"mode":"keys","elevenlabs_api_key":"el-key","gemini_api_key":"gm-key"})"));
  // Also a token that came along is not sent in keys mode.
  Json both = connected_by("keys");
  both.set("accessToken", "stray-token");
  CHECK(request_for(both).bearer.empty());
  // A key with characters JSON escapes arrives as the very same string.
  Json quoted = connected_by("keys");
  quoted.set("geminiApiKey", "gm\"key\\with\nescapes");
  CHECK(str(body(request_for(quoted)), "gemini_api_key") == "gm\"key\\with\nescapes");

  // The engine hands the host the request of its mode.
  Session s;
  CHECK(s.engine.start(connected_by("account")));
  CHECK(s.host.connects == 1 && s.host.request.bearer == "secret-token");
  CHECK(same(body(s.host.request), R"({"mode":"account"})"));
  Session k;
  CHECK(k.engine.start(connected_by("keys")));
  CHECK(k.host.connects == 1 && k.host.request.bearer.empty());
  CHECK(same(body(k.host.request), R"({"mode":"keys","elevenlabs_api_key":"el-key","gemini_api_key":"gm-key"})"));
}

static void test_session_refusals_pass_the_gateways_own_code() {
  CHECK(session_refusal(402, R"({"error":"balance_empty"})").code == "balance_empty");
  for (const char* code : {"unauthorized", "invalid_token", "balance_empty", "session_limit", "rate_limited",
                           "billing_unavailable", "accounts_unavailable", "bad_request"}) {
    const HostError refusal = session_refusal(400, std::string(R"({"error":")") + code + "\"}");
    CHECK(refusal.code == code);
    CHECK(refusal.message == std::string("the gateway refused the session (") + code + ")");
  }
  // Anything else is a plain gateway error.
  CHECK(session_refusal(503, R"({"error":"something_new"})").code == "gateway_error");
  CHECK(session_refusal(503, R"({"error":5})").code == "gateway_error");
  CHECK(session_refusal(402, R"(["balance_empty"])").code == "gateway_error");
  CHECK(session_refusal(503, "not json").code == "gateway_error");
  CHECK(session_refusal(500, "").code == "gateway_error");
  CHECK(session_refusal(503, "").message == "gateway answered HTTP 503");
  CHECK(session_refusal(201, R"({"tok":"x"})").message == "gateway answered HTTP 201");  // accepted, but no token
  // Older gateways answer these without a body.
  CHECK(session_refusal(401, "").code == "unauthorized");
  CHECK(session_refusal(401, "").message == "the gateway rejected the access token");
  CHECK(session_refusal(429, "").code == "session_limit");
  CHECK(session_refusal(429, R"({"error":"something_new"})").code == "session_limit");
  // The message never repeats what the answer carried.
  CHECK(session_refusal(402, R"({"error":"balance_empty","detail":"secret-detail"})").message.find("secret") ==
        std::string::npos);
  CHECK(session_refusal(503, R"({"error":"secret-detail"})").message.find("secret") == std::string::npos);
}

// ── Start, connect, configure ──

static void test_start_connects_and_configures_each_mode() {
  {  // captions: both directions are transcribed and translated, nothing is spoken, no playback device is needed
    Session s;
    CHECK(s.engine.start(settings("captions", "manual")));
    CHECK(s.host.connects == 1 && s.host.gateway_url == "https://bridge.example.com");
    CHECK(s.host.request.bearer == "secret-token" && s.host.request.body.empty());
    CHECK(s.host.mic_open && s.host.mic_uid == "mic");
    CHECK(s.host.source_open && s.host.source_pids == std::vector<int>({4242, 4243}));
    CHECK(!s.host.sinks[0].open && !s.host.sinks[1].open);
    CHECK(s.events.size() == 1);
    CHECK(same(s.events[0],
               R"({"type":"state","state":"connecting","outReady":false,"inReady":false,"capturing":false,)"
               R"("mock":false,"bypass":false,"outgoingMuted":false,"incomingAudioMuted":false,)"
               R"("mode":"captions","myLang":"uz","targetLang":"en","outCommit":"manual"})"));
    CHECK(s.host.sent.empty());  // nothing is sent before the socket is open
    s.engine.on_transport_open();
    CHECK(s.host.sent.size() == 1);
    CHECK(same(s.host.sent[0],
               R"({"v":1,"type":"session.configure",)"
               R"("capture_format":{"encoding":"pcm_s16le","sample_rate":16000,"channels":1},"directions":{)"
               R"("out":{"enabled":true,"source_lang":"uz","target_lang":"en","speak":false,"commit":"manual"},)"
               R"("in":{"enabled":true,"source_lang":"en","target_lang":"uz","speak":false,"commit":"vad"}}})"));
    s.engine.on_transport_open();  // a session is configured once
    CHECK(s.host.sent.size() == 1);
  }
  {  // incoming: also the call's speech in the owner's language, in the headphones
    Session s;
    CHECK(s.engine.start(settings("incoming", "vad")));
    CHECK(!s.host.sinks[0].open && s.host.sinks[1].open && s.host.sinks[1].uid == "phones");
    s.engine.on_transport_open();
    CHECK(same(at(s.host.sent[0], {"directions", "out"}),
               R"({"enabled":true,"source_lang":"uz","target_lang":"en","speak":false,"commit":"vad"})"));
    CHECK(same(at(s.host.sent[0], {"directions", "in"}),
               R"({"enabled":true,"source_lang":"en","target_lang":"uz","speak":true,"commit":"vad"})"));
  }
  {  // bidirectional, German owner and French call, no meeting app chosen, a translation model asked for
    Session s;
    Json map = settings("bidirectional", "turn_prediction", false);
    map.set("myLang", "de");
    map.set("targetLang", "fr");
    map.set("translationModel", "fast-1");
    CHECK(s.engine.start(map));
    CHECK(s.host.sinks[0].open && s.host.sinks[0].uid == "cable");
    CHECK(!s.host.sinks[1].open && !s.host.source_open && s.host.mic_open);
    CHECK(str(s.events[0], "mode") == "bidirectional" && str(s.events[0], "outCommit") == "turn_prediction");
    CHECK(str(s.events[0], "myLang") == "de" && str(s.events[0], "targetLang") == "fr");
    s.engine.on_transport_open();
    CHECK(same(s.host.sent[0],
               R"({"v":1,"type":"session.configure","translation_model":"fast-1",)"
               R"("capture_format":{"encoding":"pcm_s16le","sample_rate":16000,"channels":1},"directions":{)"
               R"("out":{"enabled":true,"source_lang":"de","target_lang":"fr","speak":true,)"
               R"("commit":"turn_prediction"},)"
               R"("in":{"enabled":false,"source_lang":"fr","target_lang":"de","speak":true,"commit":"vad"}}})"));
  }
  {  // a voice chosen for each direction travels with the configure message
    Session s;
    Json map = settings("bidirectional", "manual");
    map.set("outVoiceId", "voiceChosenOut01");
    map.set("inVoiceId", "voiceChosenIn001");
    CHECK(s.engine.start(map));
    s.engine.on_transport_open();
    CHECK(same(s.host.sent[0],
               R"({"v":1,"type":"session.configure",)"
               R"("capture_format":{"encoding":"pcm_s16le","sample_rate":16000,"channels":1},"directions":{)"
               R"("out":{"enabled":true,"source_lang":"uz","target_lang":"en","speak":true,"commit":"manual"},)"
               R"("in":{"enabled":true,"source_lang":"en","target_lang":"uz","speak":true,"commit":"vad"}},)"
               R"("voices":{"out":"voiceChosenOut01","in":"voiceChosenIn001"}})"));
  }
  {  // only the incoming voice chosen: the outgoing one is left to the gateway
    Session s;
    Json map = settings("bidirectional", "manual");
    map.set("inVoiceId", "voiceChosenIn001");
    CHECK(s.engine.start(map));
    s.engine.on_transport_open();
    CHECK(same(at(s.host.sent[0], {"voices"}), R"({"in":"voiceChosenIn001"})"));
  }
  {  // a malformed id is left out, and with no voice left there is no `voices` member; the start still succeeds
    Session s;
    Json map = settings("bidirectional", "manual");
    map.set("outVoiceId", "bad id");
    CHECK(s.engine.start(map));
    s.engine.on_transport_open();
    CHECK(s.host.sent.size() == 1 && str(s.host.sent[0], "type") == "session.configure");
    CHECK(!has(s.host.sent[0], "voices"));
  }
}

/// Starts a session that must be refused and returns the error code it was refused with.
static std::string refusal(const Json& map, const std::function<void(FakeHost&)>& arrange = nullptr) {
  Session s;
  if (arrange) arrange(s.host);
  CHECK(s.engine.start(map));  // the map is well-formed; it is the route that is wrong
  CHECK(s.events.size() == 1 && str(s.events[0], "type") == "error" && yes(s.events[0], "fatal"));
  CHECK(!str(s.events[0], "message").empty());
  CHECK(s.host.connects == 0 && s.host.nothing_open());
  return s.events.empty() ? "" : str(s.events[0], "code");
}

static void test_unusable_routes_are_refused() {
  Json map = settings("bidirectional", "manual");
  map.set("virtualMicUid", "mic");
  CHECK(refusal(map) == "unsafe_route");  // the call would hear the microphone twice
  map = settings("incoming", "manual");
  map.set("headphonesUid", "cable");
  CHECK(refusal(map) == "unsafe_route");  // the call would hear its own translation

  map = settings("bidirectional", "manual");
  map.set("virtualMicUid", Json());
  CHECK(refusal(map) == "no_virtual_mic");
  const Json both_ways = settings("bidirectional", "manual");
  CHECK(refusal(both_ways, [](FakeHost& host) { host.devices.erase("cable"); }) == "no_virtual_mic");
  CHECK(refusal(both_ways, [](FakeHost& host) { host.devices["cable"].output_channels = 0; }) == "no_virtual_mic");

  // Incoming speech is only ever played on a physical device that exists.
  const Json incoming = settings("incoming", "manual");
  const Json captions = settings("captions", "manual");
  CHECK(refusal(incoming, [](FakeHost& host) { host.devices["phones"].is_virtual = true; }) == "no_headphones");
  CHECK(refusal(incoming, [](FakeHost& host) { host.devices.erase("phones"); }) == "no_headphones");
  CHECK(refusal(captions, [](FakeHost& host) { host.devices.erase("mic"); }) == "no_microphone");
  CHECK(refusal(captions, [](FakeHost& host) { host.devices["mic"].input_channels = 0; }) == "no_microphone");

  // The host could not open a device: its own reason is reported, or a default one when it gives none.
  CHECK(refusal(both_ways, [](FakeHost& host) {
          host.mic_fails = true;
          host.failure = {"wasapi", "IAudioClient::Initialize failed"};
        }) == "wasapi");
  CHECK(refusal(both_ways, [](FakeHost& host) { host.sink_fails[1] = true; }) == "device");
  CHECK(refusal(captions, [](FakeHost& host) { host.source_fails = true; }) == "source_gone");

  // A device that is not needed is not looked at: captions play nothing, and without a meeting app neither does
  // the incoming direction.
  Session s;
  s.host.devices.erase("phones");
  s.host.devices.erase("cable");
  CHECK(s.engine.start(settings("captions", "manual")) && str(s.events[0], "state") == "connecting");
  Session t;
  t.host.devices.erase("phones");
  CHECK(t.engine.start(settings("incoming", "manual", false)) && str(t.events[0], "state") == "connecting");

  // What the microphone failure left open was closed again, and the engine is ready for a good start.
  Session u;
  u.host.mic_fails = true;
  CHECK(u.engine.start(settings("bidirectional", "manual")));
  CHECK(logged(u.host, {"open_sink:out", "open_sink:in", "close_sink:out", "close_sink:in"}));
  u.host.mic_fails = false;
  u.forget();
  CHECK(u.engine.start(settings("bidirectional", "manual")));
  CHECK(u.events.size() == 1 && str(u.events[0], "state") == "connecting" && u.host.connects == 1);

  // One session at a time.
  u.forget();
  CHECK(u.engine.start(settings("captions", "manual")));
  CHECK(u.events.size() == 1);
  CHECK(same(u.events[0], R"({"type":"error","code":"busy","message":"a session is already running","fatal":false})"));
  CHECK(u.host.connects == 1 && u.host.log.empty());
}

static void test_first_connection_failure_ends_the_session() {
  Session s;
  CHECK(s.engine.start(settings("incoming", "manual")));
  s.forget();
  s.engine.on_transport_closed("unauthorized", "the gateway rejected the access token");
  CHECK(s.events.size() == 3);
  CHECK(same(s.events[0], R"({"type":"error","code":"unauthorized","fatal":true,)"
                          R"("message":"the gateway rejected the access token"})"));
  CHECK(str(s.events[1], "state") == "stopping" && str(s.events[1], "mode") == "incoming");
  CHECK(same(s.events[2], kIdleState));
  CHECK(s.host.closes == 1 && !s.host.connected && s.host.nothing_open());

  // It is not retried, and whatever that connection still delivers is ignored.
  s.forget();
  s.host.now += 20'000'000;
  s.engine.tick();
  s.engine.on_transport_open();
  s.ready(true, true);
  s.caption("caption.final", "out", 1, 2);
  s.engine.on_transport_closed("gateway_unreachable", "again");
  CHECK(s.events.empty() && s.host.log.empty());

  Session t;
  CHECK(t.engine.start(settings("incoming", "manual")));
  t.engine.on_transport_closed("", "no response from the gateway");
  CHECK(str(t.events[1], "code") == "gateway_unreachable" && yes(t.events[1], "fatal"));
}

// ── Ready ──

static void test_ready_reports_state_and_opens_capture() {
  {  // push-to-talk with a meeting app: the meeting's audio flows at once, the microphone waits for the button
    Session s;
    CHECK(s.engine.start(settings("captions", "manual")));
    s.engine.on_transport_open();
    s.forget();
    s.ready(true, true, 24'000, 24'000, true);
    CHECK(s.host.sent.size() == 1);
    CHECK(same(s.host.sent[0], R"({"v":1,"type":"capture.start","direction":"in","generation":1})"));
    CHECK(s.events.size() == 1);
    CHECK(same(s.events[0],
               R"({"type":"state","state":"active","outReady":true,"inReady":true,"capturing":true,"mock":true,)"
               R"("bypass":false,"outgoingMuted":false,"incomingAudioMuted":false,)"
               R"("mode":"captions","myLang":"uz","targetLang":"en","outCommit":"manual"})"));
    s.host.now += 20'000;
    s.source(2 * kFrame);
    s.mic(kFrame);
    CHECK(s.host.frames.size() == 2);
    for (std::size_t n = 0; n < s.host.frames.size(); n++) {
      const AudioFrame& frame = s.host.frames[n];
      CHECK(frame.kind == AudioFrame::Kind::capture && frame.direction == kIn && frame.flags == 0);
      CHECK(frame.generation == 1 && frame.sequence == n && frame.turn_id == 0);
      CHECK(frame.timestamp_us == s.host.now && frame.payload.size() == kFrame);
      CHECK(frame.payload.front() == recorded(n * kFrame) && frame.payload.back() == recorded(n * kFrame + kFrame - 1));
    }

    // The gateway announces again when a provider drops: the state follows, capture is not started twice.
    s.forget();
    s.ready(false, true);
    CHECK(s.host.sent.empty() && s.events.size() == 1);
    CHECK(str(s.events[0], "state") == "active" && !yes(s.events[0], "outReady") && yes(s.events[0], "inReady"));
    CHECK(!yes(s.events[0], "mock"));
  }
  {  // push-to-talk with no meeting app: nothing is captured until the button is held
    Session s;
    CHECK(s.engine.start(settings("captions", "manual", false)));
    s.engine.on_transport_open();
    s.forget();
    s.ready(true, false);
    CHECK(s.host.sent.empty() && s.events.size() == 1);
    CHECK(str(s.events[0], "state") == "ready" && yes(s.events[0], "outReady") && !yes(s.events[0], "inReady"));
    CHECK(!yes(s.events[0], "capturing"));
  }
  {  // an automatic turn mode opens the outgoing lane by itself
    Session s;
    CHECK(s.engine.start(settings("incoming", "vad")));
    s.engine.on_transport_open();
    s.forget();
    s.ready(true, true);
    CHECK(s.host.sent.size() == 2);
    CHECK(same(s.host.sent[0], R"({"v":1,"type":"capture.start","direction":"in","generation":1})"));
    CHECK(same(s.host.sent[1], R"({"v":1,"type":"capture.start","direction":"out","generation":1})"));
    CHECK(str(s.events[0], "state") == "active" && yes(s.events[0], "capturing"));
    s.mic(kFrame);
    CHECK(s.host.frames.size() == 1 && s.host.frames[0].direction == kOut);
    // The talk button means nothing here.
    s.forget();
    s.engine.ptt_down();
    s.engine.ptt_up();
    CHECK(s.events.empty() && s.host.sent.empty());
  }
  {  // a direction is ready only when the gateway says both "enabled" and "ready"; until then it stays shut
    Session s;
    CHECK(s.engine.start(settings("incoming", "vad")));
    s.engine.on_transport_open();
    s.forget();
    s.text(R"({"v":1,"type":"session.ready","providers":{"mock":false},"directions":{)"
           R"("out":{"enabled":false,"ready":true},"in":{"enabled":true,"ready":false}}})");
    CHECK(s.host.sent.empty() && str(s.events[0], "state") == "ready" && !yes(s.events[0], "capturing"));
    CHECK(!yes(s.events[0], "outReady") && !yes(s.events[0], "inReady"));
    s.mic(kFrame);
    s.source(kFrame);
    CHECK(s.host.frames.empty());
  }
}

// ── Push-to-talk ──

static void test_push_to_talk_turn() {
  Session s;
  CHECK(s.engine.start(settings("bidirectional", "manual", false)));
  s.engine.ptt_down();  // not connected yet
  s.engine.on_transport_open();
  s.engine.ptt_down();  // not ready yet
  CHECK(s.host.sent.size() == 1 && s.events.size() == 1);
  s.ready(true, false);
  s.forget();

  s.mic(kFrame);  // nothing leaves the machine unless the talk button is held
  CHECK(s.host.frames.empty());

  s.engine.ptt_down();
  CHECK(s.host.sent.size() == 1);
  CHECK(same(s.host.sent[0], R"({"v":1,"type":"capture.start","direction":"out","generation":1})"));
  CHECK(s.events.size() == 1 && str(s.events[0], "state") == "ready" && yes(s.events[0], "capturing"));
  s.engine.ptt_down();  // already held
  CHECK(s.host.sent.size() == 1 && s.events.size() == 1);

  // The microphone delivers pieces of any size; the gateway gets 20 ms frames, in order, numbered from zero.
  const std::size_t first = s.mic_fed;
  const std::uint64_t began = s.host.now;
  s.mic(1000);
  s.host.now += 20'000;
  s.mic(280);
  s.host.now += 20'000;
  s.mic(kFrame + 100);
  CHECK(s.host.frames.size() == 3);
  for (std::size_t n = 0; n < s.host.frames.size(); n++) {
    const AudioFrame& frame = s.host.frames[n];
    CHECK(frame.kind == AudioFrame::Kind::capture && frame.direction == kOut && frame.flags == 0);
    CHECK(frame.generation == 1 && frame.sequence == n && frame.turn_id == 0);
    CHECK(frame.timestamp_us == began + n * 20'000);
    CHECK(frame.payload.size() == kFrame);
    bool intact = true;
    for (std::size_t i = 0; i < frame.payload.size(); i++)
      intact = intact && frame.payload[i] == recorded(first + n * kFrame + i);
    CHECK(intact);
  }

  s.host.now += 1'000'000;
  s.engine.ptt_up();
  // The commit follows the last frame on the same socket.
  CHECK(logged(s.host, {"capture.start", "frame:out", "frame:out", "frame:out", "turn.commit", "capture.pause"}));
  CHECK(same(s.host.sent[1], R"({"v":1,"type":"turn.commit","direction":"out"})"));
  CHECK(same(s.host.sent[2], R"({"v":1,"type":"capture.pause","direction":"out"})"));
  CHECK(s.events.size() == 2 && !yes(s.events[1], "capturing"));
  s.engine.ptt_up();  // not held
  CHECK(s.host.sent.size() == 3 && s.events.size() == 2);
  s.mic(3 * kFrame);
  CHECK(s.host.frames.size() == 3);

  // The next press continues the numbering: a sequence only restarts with a new generation.
  s.engine.ptt_down();
  s.mic(kFrame);
  CHECK(same(s.host.sent[3], R"({"v":1,"type":"capture.start","direction":"out","generation":1})"));
  CHECK(s.host.frames.size() == 4 && s.host.frames[3].generation == 1 && s.host.frames[3].sequence == 3);
}

// ── Gateway messages -> bridge events ──

static void test_gateway_messages_become_bridge_events() {
  Session s;
  s.go(settings("captions", "manual"));

  s.caption("caption.partial", "out", 1, 1, "Sal");
  s.caption("caption.final", "out", 1, 1, "Salom");
  s.caption("translation.delta", "out", 1, 1, "Hel");
  s.caption("translation.final", "out", 1, 1, "Hello");
  CHECK(s.events.size() == 4);
  CHECK(same(s.events[0], R"({"type":"caption","direction":"out","turnId":1,"kind":"partial","text":"Sal"})"));
  CHECK(same(s.events[1], R"({"type":"caption","direction":"out","turnId":1,"kind":"final","text":"Salom"})"));
  CHECK(same(s.events[2], R"({"type":"caption","direction":"out","turnId":1,"kind":"translationDelta","text":"Hel"})"));
  CHECK(same(s.events[3],
             R"({"type":"caption","direction":"out","turnId":1,"kind":"translationFinal","text":"Hello"})"));

  // A turn the gateway left untranslated and unspoken: the reason goes with it, the text is empty.
  s.forget();
  s.caption("caption.final", "in", 1, 1, "O\\u02bbzbekcha gap");
  s.text(R"({"v":1,"type":"turn.skipped","direction":"in","turn_id":1,"generation":1,"reason":"same_language"})");
  s.text(R"({"v":1,"type":"turn.skipped","direction":"out","turn_id":2,"generation":1,"reason":"echo"})");
  CHECK(s.events.size() == 3);
  CHECK(str(s.events[0], "direction") == "in" && str(s.events[0], "text") == "O\xCA\xBBzbekcha gap");
  CHECK(same(s.events[1],
             R"({"type":"caption","direction":"in","turnId":1,"kind":"skipped","text":"","reason":"same_language"})"));
  CHECK(same(s.events[2],
             R"({"type":"caption","direction":"out","turnId":2,"kind":"skipped","text":"","reason":"echo"})"));

  // Metrics are renamed for the bridge; stages that did not run stay absent, the frame counter is not passed on.
  s.forget();
  s.text(R"({"v":1,"type":"metrics","direction":"out","turn_id":1,"generation":1,"stt_commit_ms":120,)"
         R"("translate_first_ms":300,"translate_total_ms":450,"tts_first_audio_ms":610,"tts_total_ms":900,)"
         R"("audio_ms":1500,"model":"fast-1","dropped_frames":0})");
  s.text(R"({"v":1,"type":"metrics","direction":"in","turn_id":1,"generation":1,"stt_commit_ms":80,)"
         R"("dropped_frames":2})");
  CHECK(s.events.size() == 2);
  CHECK(same(s.events[0],
             R"({"type":"metrics","direction":"out","turnId":1,"sttCommitMs":120,"translateFirstMs":300,)"
             R"("translateTotalMs":450,"ttsFirstAudioMs":610,"ttsTotalMs":900,"audioMs":1500,"model":"fast-1"})"));
  CHECK(same(s.events[1], R"({"type":"metrics","direction":"in","turnId":1,"sttCommitMs":80})"));

  // An error that is not fatal is reported and the session goes on.
  s.forget();
  s.text(R"({"v":1,"type":"error","code":"translation_failed","message":"model timed out","direction":"out",)"
         R"("turn_id":1,"fatal":false})");
  s.text(R"({"v":1,"type":"error","fatal":false})");
  CHECK(s.events.size() == 2);
  CHECK(same(s.events[0], R"({"type":"error","code":"translation_failed","message":"model timed out",)"
                          R"("direction":"out","fatal":false})"));
  CHECK(same(s.events[1], R"({"type":"error","code":"error","message":"","fatal":false})"));
  CHECK(s.host.connected);

  // Not for the interface: an older generation, no usable direction, other message types, and anything malformed.
  s.forget();
  s.caption("caption.final", "out", 3, 0);
  s.caption("caption.final", "sideways", 3, 1);
  s.text(R"({"v":1,"type":"caption.final","turn_id":3,"generation":1,"text":"x"})");
  s.text(R"({"v":1,"type":"metrics","turn_id":3})");
  s.text(R"({"v":1,"type":"pong","t":1})");
  s.text(R"({"v":1,"direction":"out"})");
  s.text(R"([1,2,3])");
  s.text("not json");
  s.text("");
  CHECK(s.events.empty() && s.host.log.empty());

  // A fatal error ends the session.
  s.text(R"({"v":1,"type":"error","code":"session_expired","message":"the session ran out","fatal":true})");
  CHECK(s.events.size() == 3);
  CHECK(same(s.events[0], R"({"type":"error","code":"session_expired","message":"the session ran out","fatal":true})"));
  CHECK(str(s.events[1], "state") == "stopping");
  CHECK(same(s.events[2], kIdleState));
  CHECK(!s.host.connected && s.host.closes == 1 && s.host.nothing_open());
}

static void test_account_balance_becomes_a_balance_event() {
  Session s;
  s.go(connected_by("account"));
  s.text(R"({"v":1,"type":"account.balance","balance_units":4200})");
  CHECK(s.events.size() == 1);
  CHECK(same(s.events[0], R"({"type":"balance","balanceUnits":4200})"));
  s.text(R"({"v":1,"type":"account.balance","balance_units":0})");
  CHECK(s.events.size() == 2 && same(s.events[1], R"({"type":"balance","balanceUnits":0})"));

  // Only a whole number of units is a balance.
  s.forget();
  s.text(R"({"v":1,"type":"account.balance","balance_units":12.5})");
  s.text(R"({"v":1,"type":"account.balance","balance_units":"4200"})");
  s.text(R"({"v":1,"type":"account.balance"})");
  CHECK(s.events.empty());
  CHECK(s.host.log.empty() && s.host.connected);  // nothing is answered and the session goes on
}

// ── Synthesized speech -> playback ──

static void test_synthesized_speech_is_played_and_reported() {
  Session s;
  CHECK(s.engine.start(settings("bidirectional", "manual")));
  s.engine.on_transport_open();
  s.ready(true, true, 22'050, 24'000);  // each direction plays at the rate announced for it
  FakeHost::Sink& out = s.host.sinks[0];
  FakeHost::Sink& in = s.host.sinks[1];
  CHECK(out.open && out.uid == "cable" && in.open && in.uid == "phones");

  s.engine.ptt_down();
  s.mic(kFrame);
  s.engine.ptt_up();  // the end-to-end clock starts here
  s.forget();

  // An incoming turn that fits one frame: both reports, in order. It does not answer the released button.
  s.synthesized(kIn, 1, 7, 480, true);
  CHECK(in.writes.size() == 1 && in.writes[0] == std::make_pair(std::size_t{480}, 24'000) && in.end_inputs == 1);
  CHECK(in.audio.front() == 7 && out.writes.empty());
  in.consumed = in.written;
  s.engine.tick();
  CHECK(s.host.sent.size() == 2 && s.events.empty());
  CHECK(same(s.host.sent[0], R"({"v":1,"type":"playback.start","direction":"in","turn_id":7,"generation":1})"));
  CHECK(same(s.host.sent[1], R"({"v":1,"type":"playback.end","direction":"in","turn_id":7,"generation":1})"));
  s.forget();

  s.host.now += 300'000;
  s.synthesized(kOut, 1, 1, 960, false);
  s.synthesized(kOut, 1, 1, 960, false);
  CHECK(out.writes.size() == 2 && out.writes[0] == std::make_pair(std::size_t{960}, 22'050));
  CHECK(out.audio.size() == 1920 && out.audio.front() == 1 && out.audio.back() == 1 && out.end_inputs == 0);
  s.engine.tick();  // queued, but the device has not played any of it yet
  CHECK(s.host.sent.empty() && s.events.empty());

  out.consumed = 10;
  s.host.now += 50'000;
  s.engine.tick();
  CHECK(s.host.sent.size() == 1);
  CHECK(same(s.host.sent[0], R"({"v":1,"type":"playback.start","direction":"out","turn_id":1,"generation":1})"));
  // Released 350 ms ago: the client's own figure is published at once...
  CHECK(s.events.size() == 1 && same(s.events[0], R"({"type":"metrics","direction":"out","turnId":1,"e2eMs":350})"));
  s.engine.tick();
  CHECK(s.host.sent.size() == 1 && s.events.size() == 1);

  // ...and once more with the gateway's metrics for that turn.
  s.forget();
  const char* metrics =
      R"({"v":1,"type":"metrics","direction":"out","turn_id":1,"generation":1,"tts_first_audio_ms":610})";
  s.text(metrics);
  s.text(metrics);
  CHECK(same(s.events[0], R"({"type":"metrics","direction":"out","turnId":1,"ttsFirstAudioMs":610,"e2eMs":350})"));
  CHECK(same(s.events[1], R"({"type":"metrics","direction":"out","turnId":1,"ttsFirstAudioMs":610})"));

  // The last frame of a turn may be empty. The turn ends when the device has played all of it, not before.
  s.forget();
  s.synthesized(kOut, 1, 1, 0, true);
  CHECK(out.writes.size() == 2 && out.end_inputs == 1);
  out.consumed = out.written - 1;
  s.engine.tick();
  CHECK(s.host.sent.empty());
  out.consumed = out.written;
  s.engine.tick();
  CHECK(s.host.sent.size() == 1);
  CHECK(same(s.host.sent[0], R"({"v":1,"type":"playback.end","direction":"out","turn_id":1,"generation":1})"));
  s.engine.tick();
  CHECK(s.host.sent.size() == 1 && s.events.empty());

  // Two turns queued back to back are reported one after the other, as the device reaches them.
  s.forget();
  s.synthesized(kOut, 1, 2, 960, true);
  s.synthesized(kOut, 1, 3, 960, true);
  out.consumed = out.written - 480;  // all of turn 2, none of turn 3
  s.engine.tick();
  CHECK(s.host.sent.size() == 2 && num(s.host.sent[0], "turn_id") == 2 && num(s.host.sent[1], "turn_id") == 2);
  CHECK(str(s.host.sent[0], "type") == "playback.start" && str(s.host.sent[1], "type") == "playback.end");
  out.consumed = out.written;
  s.engine.tick();
  CHECK(s.host.sent.size() == 4 && num(s.host.sent[2], "turn_id") == 3 && num(s.host.sent[3], "turn_id") == 3);
  CHECK(s.events.empty());  // the released button was already answered by turn 1

  // Never played: a frame of another generation, a capture frame, bytes that are not a frame.
  s.forget();
  const std::size_t writes = out.writes.size();
  s.synthesized(kOut, 0, 4, 960, true);
  s.synthesized(kOut, 2, 4, 960, true);
  AudioFrame capture;
  capture.payload.assign(kFrame, 0);
  capture.generation = 1;
  std::vector<std::uint8_t> encoded;
  CHECK(encode_frame(capture, encoded) == FrameError::none);
  s.engine.on_transport_binary(encoded.data(), encoded.size());
  s.engine.on_transport_binary(encoded.data(), 10);
  s.engine.on_transport_binary(nullptr, 0);
  CHECK(out.writes.size() == writes && s.events.empty());

  // A session that plays nothing ignores synthesized frames altogether.
  Session quiet;
  quiet.go(settings("captions", "manual"));
  quiet.synthesized(kOut, 1, 1, 960, true);
  quiet.synthesized(kIn, 1, 1, 960, true);
  quiet.engine.tick();
  CHECK(quiet.events.empty() && quiet.host.log.empty());
}

// ── Panic ──

static void test_panic_discards_everything() {
  Session s;
  s.go(settings("bidirectional", "manual"));
  s.caption("caption.final", "out", 1, 1);
  s.synthesized(kOut, 1, 1, 960, false);
  s.synthesized(kIn, 1, 1, 960, false);
  s.forget();

  s.engine.panic();
  // Silence first, before any teardown: both queues muted and emptied, then the connection, then the devices.
  CHECK(logged(s.host, {"mute:out", "flush:out", "mute:in", "flush:in", "flush:out", "flush:in", "close", "close_mic",
                        "close_source", "close_sink:out", "close_sink:in"}));
  CHECK(s.host.sinks[0].muted && s.host.sinks[1].muted);
  CHECK(s.host.sinks[0].consumed == s.host.sinks[0].written && s.host.sinks[1].consumed == s.host.sinks[1].written);
  CHECK(!s.host.connected && s.host.nothing_open());
  CHECK(s.events.size() == 2 && str(s.events[0], "state") == "stopping");
  CHECK(same(s.events[1],
             R"({"type":"state","state":"idle","outReady":false,"inReady":false,"capturing":false,"mock":false,)"
             R"("bypass":false,"outgoingMuted":false,"incomingAudioMuted":false,)"
             R"("message":"Panic stop: all audio discarded"})"));

  // Whatever was still on its way is dropped.
  s.forget();
  s.synthesized(kOut, 2, 1, 960, true);
  s.caption("caption.final", "out", 2, 2);
  s.ready(true, true);
  s.mic(kFrame);
  s.engine.ptt_down();
  s.host.now += 5'000'000;
  s.engine.tick();
  CHECK(s.events.empty() && s.host.log.empty());

  // The next session is fenced off from the old one: a new generation, fresh unmuted queues, turn ids that go on.
  CHECK(s.engine.start(settings("bidirectional", "manual")));
  s.engine.on_transport_open();
  s.ready(true, true);
  CHECK(!has(s.events[0], "message"));
  CHECK(same(s.host.sent.back(), R"({"v":1,"type":"capture.start","direction":"in","generation":2})"));
  CHECK(!s.host.sinks[0].muted && !s.host.sinks[1].muted);
  s.forget();
  s.synthesized(kOut, 1, 1, 960, true);  // a late frame of the session that was stopped
  CHECK(s.host.sinks[0].writes.empty());
  s.synthesized(kOut, 2, 5, 960, true);
  CHECK(s.host.sinks[0].writes.size() == 1);
  s.caption("caption.final", "out", 1, 1);
  CHECK(s.events.empty());
  s.caption("caption.final", "out", 1, 2);
  CHECK(s.events.size() == 1 && num(s.events[0], "turnId") == 2);
  // Only the new session's turn is reported as played; the turns the panic cut off are forgotten.
  s.forget();
  s.host.sinks[0].consumed = s.host.sinks[0].written;
  s.engine.tick();
  CHECK(s.host.sent.size() == 2 && num(s.host.sent[0], "turn_id") == 5 && num(s.host.sent[1], "turn_id") == 5);

  // With no session running there is nothing to discard; the interface is still told.
  Session idle;
  idle.engine.panic();
  CHECK(idle.events.size() == 1 && str(idle.events[0], "state") == "idle");
  CHECK(str(idle.events[0], "message") == "Panic stop: all audio discarded" && idle.host.log.empty());
}

// ── Mute and bypass ──

static void test_outgoing_mute_cancels_the_turn_in_flight() {
  Session s;
  s.go(settings("bidirectional", "manual", false));
  s.engine.ptt_down();
  s.mic(kFrame);
  s.synthesized(kOut, 1, 1, 960, false);
  CHECK(s.host.frames.size() == 1 && s.host.sinks[0].writes.size() == 1);
  s.forget();

  s.engine.set_outgoing_muted(true);
  CHECK(s.host.sent.size() == 1);
  CHECK(same(s.host.sent[0], R"({"v":1,"type":"turn.cancel","direction":"out","generation":2})"));
  CHECK(logged(s.host, {"flush:out", "turn.cancel"}));
  CHECK(s.events.size() == 1 && str(s.events[0], "state") == "ready");
  CHECK(yes(s.events[0], "outgoingMuted") && !yes(s.events[0], "capturing"));  // the button was let go for the user

  // Fenced: the cancelled generation is ignored, and while muted nothing is captured, played or reported as played.
  s.mic(kFrame);
  s.engine.ptt_down();
  s.synthesized(kOut, 1, 1, 960, true);
  s.synthesized(kOut, 2, 2, 960, true);
  s.caption("caption.final", "out", 1, 1);
  s.host.sinks[0].consumed = s.host.sinks[0].written;
  s.engine.tick();
  CHECK(s.host.frames.empty() && s.host.sinks[0].writes.size() == 1 && s.host.sent.size() == 1 && s.events.size() == 1);
  s.caption("caption.final", "out", 2, 2);  // captions of the new generation still arrive
  CHECK(s.events.size() == 2 && str(s.events[1], "type") == "caption");

  s.forget();
  s.engine.set_outgoing_muted(false);
  CHECK(s.host.sent.empty() && s.events.size() == 1 && !yes(s.events[0], "outgoingMuted"));
  s.engine.ptt_down();
  s.mic(kFrame);
  CHECK(same(s.host.sent[0], R"({"v":1,"type":"capture.start","direction":"out","generation":2})"));
  CHECK(s.host.frames.size() == 1 && s.host.frames[0].generation == 2 && s.host.frames[0].sequence == 0);

  // In an automatic mode the lane closes with the mute and opens again without it; the other lane is untouched.
  Session h;
  h.go(settings("incoming", "vad"));
  h.mic(kFrame);
  CHECK(h.host.frames.size() == 1);
  h.forget();
  h.engine.set_outgoing_muted(true);
  CHECK(h.host.sent.size() == 1);
  CHECK(same(h.host.sent[0], R"({"v":1,"type":"turn.cancel","direction":"out","generation":2})"));
  h.mic(kFrame);
  CHECK(h.host.frames.empty());
  h.source(kFrame);
  CHECK(h.host.frames.size() == 1 && h.host.frames[0].direction == kIn && h.host.frames[0].generation == 1);
  h.forget();
  h.engine.set_outgoing_muted(false);
  CHECK(h.host.sent.size() == 1);
  CHECK(same(h.host.sent[0], R"({"v":1,"type":"capture.start","direction":"out","generation":2})"));
  h.mic(kFrame);
  CHECK(h.host.frames.size() == 1 && h.host.frames[0].generation == 2 && h.host.frames[0].sequence == 0);

  // Incoming audio mute silences the headphones and nothing else.
  h.forget();
  h.engine.set_incoming_audio_muted(true);
  CHECK(h.host.sinks[1].muted && h.host.sent.empty());
  CHECK(h.events.size() == 1 && yes(h.events[0], "incomingAudioMuted") && !yes(h.events[0], "outgoingMuted"));
  h.synthesized(kIn, 1, 1, 960, true);  // still queued: the device drains it in silence
  CHECK(h.host.sinks[1].writes.size() == 1);
  h.engine.set_incoming_audio_muted(false);
  CHECK(!h.host.sinks[1].muted && !yes(h.events[1], "incomingAudioMuted"));

  // Muting before a session exists only changes the reported state.
  Session idle;
  idle.engine.set_outgoing_muted(true);
  CHECK(idle.events.size() == 1 && str(idle.events[0], "state") == "idle" && yes(idle.events[0], "outgoingMuted"));
  CHECK(idle.host.log.empty());
}

static void test_bypass_routes_the_microphone_to_the_call() {
  // Without a virtual microphone there is nowhere to route it.
  Session c;
  c.go(settings("captions", "vad", false));
  c.engine.set_bypass(true);
  CHECK(c.events.size() == 1 && c.host.sent.empty());
  CHECK(same(c.events[0], R"({"type":"error","code":"no_virtual_mic","fatal":false,)"
                          R"("message":"bypass needs the virtual microphone"})"));

  Session s;
  s.go(settings("bidirectional", "vad", false));
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 1);
  s.forget();

  s.engine.set_bypass(true);
  CHECK(s.host.sent.size() == 1);
  CHECK(same(s.host.sent[0], R"({"v":1,"type":"turn.cancel","direction":"out","generation":2})"));
  CHECK(s.events.size() == 1 && yes(s.events[0], "bypass") && yes(s.events[0], "capturing"));
  s.engine.set_bypass(true);  // already on
  CHECK(s.events.size() == 1);

  // The microphone goes straight into the virtual microphone, at its own rate, and not to the server.
  const std::size_t first = s.mic_fed;
  FakeHost::Sink& out = s.host.sinks[0];
  s.mic(2 * kFrame);
  CHECK(s.host.frames.empty());
  CHECK(out.writes.size() == 2 && out.writes[0] == std::make_pair(kFrame, 16'000));
  CHECK(out.audio.size() == 2 * kFrame && out.audio.front() == recorded(first));
  CHECK(out.audio.back() == recorded(first + 2 * kFrame - 1));
  s.synthesized(kOut, 2, 1, 960, true);  // translated speech is not mixed in
  CHECK(out.writes.size() == 2);

  s.forget();
  const int flushes = out.flushes;
  s.engine.set_bypass(false);
  CHECK(out.flushes == flushes + 1);
  CHECK(s.host.sent.size() == 1);
  CHECK(same(s.host.sent[0], R"({"v":1,"type":"capture.start","direction":"out","generation":2})"));
  CHECK(s.events.size() == 1 && !yes(s.events[0], "bypass") && yes(s.events[0], "capturing"));
  s.mic(kFrame);
  CHECK(out.writes.size() == 2 && s.host.frames.size() == 1 && s.host.frames[0].generation == 2);
}

// ── Connection loss ──

static void test_connection_loss_degrades_and_reconnects() {
  Session s;
  s.go(settings("captions", "manual"));
  s.caption("caption.final", "out", 1, 1);
  s.caption("caption.final", "out", 2, 1);
  s.caption("caption.final", "in", 1, 1);
  s.source(2 * kFrame);
  CHECK(num(s.events[0], "turnId") == 1 && num(s.events[1], "turnId") == 2 && num(s.events[2], "turnId") == 1);
  CHECK(s.host.frames.size() == 2 && s.host.frames[1].sequence == 1);
  s.forget();

  s.engine.on_transport_closed("gateway_unreachable", "the gateway closed the connection (1006)");
  CHECK(s.host.closes == 1 && !s.host.connected);
  CHECK(s.host.mic_open && s.host.source_open);  // the devices stay as they are
  CHECK(s.events.size() == 1);
  CHECK(same(s.events[0],
             R"({"type":"state","state":"degraded","outReady":false,"inReady":false,"capturing":false,"mock":false,)"
             R"("bypass":false,"outgoingMuted":false,"incomingAudioMuted":false,)"
             R"x("message":"Connection lost — reconnecting (attempt 1 of 5)",)x"
             R"("mode":"captions","myLang":"uz","targetLang":"en","outCommit":"manual"})"));
  s.source(kFrame);
  s.caption("caption.final", "out", 3, 1);
  CHECK(s.host.frames.empty() && s.events.size() == 1);

  // The first retry waits between a quarter and half a second.
  s.host.now += 240'000;
  s.engine.tick();
  CHECK(s.host.connects == 1);
  s.host.now += 260'000;
  s.engine.tick();
  CHECK(s.host.connects == 2 && s.host.connected);
  s.engine.tick();
  CHECK(s.host.connects == 2);

  // A fresh session on the new connection: configured again, a new generation, nothing replayed.
  s.forget();
  s.engine.on_transport_open();
  CHECK(s.host.sent.size() == 1 && str(s.host.sent[0], "type") == "session.configure");
  s.ready(true, true);
  CHECK(same(s.host.sent[1], R"({"v":1,"type":"capture.start","direction":"in","generation":2})"));
  CHECK(s.events.size() == 1 && str(s.events[0], "state") == "active" && !has(s.events[0], "message"));
  s.forget();
  s.source(kFrame);
  CHECK(s.host.frames.size() == 1 && s.host.frames[0].generation == 2 && s.host.frames[0].sequence == 0);

  // The gateway numbers turns from 1 again; the ids shown go on from where each direction was.
  s.caption("caption.final", "out", 1, 2);
  s.caption("caption.final", "in", 1, 2);
  s.caption("caption.final", "out", 2, 1);  // tagged with the generation of the lost connection
  CHECK(s.events.size() == 2 && num(s.events[0], "turnId") == 3 && num(s.events[1], "turnId") == 2);

  // A session that recovered starts counting attempts from one again.
  s.forget();
  s.engine.on_transport_closed("gateway_unreachable", "reset");
  CHECK(str(s.events[0], "message") == "Connection lost — reconnecting (attempt 1 of 5)");
  s.host.now += 500'000;
  s.engine.tick();
  s.engine.on_transport_open();
  s.ready(true, true);
  s.forget();
  s.caption("caption.final", "out", 1, 3);
  CHECK(num(s.events[0], "turnId") == 4);

  // A turn that was playing when the connection dropped is cut off, and never reported on the new connection.
  Session p;
  p.go(settings("incoming", "manual"));
  FakeHost::Sink& in = p.host.sinks[1];
  p.synthesized(kIn, 1, 1, 960, true);
  p.engine.on_transport_closed("gateway_unreachable", "reset");
  CHECK(in.flushes == 1 && in.consumed == in.written);
  p.synthesized(kIn, 2, 2, 960, true);  // nothing is played while there is no connection
  CHECK(in.writes.size() == 1);
  p.host.now += 500'000;
  p.engine.tick();
  p.engine.on_transport_open();
  p.ready(true, true);
  p.forget();
  in.consumed = in.written + 1;
  p.engine.tick();
  CHECK(p.host.sent.empty());
}

static void test_reconnecting_gives_up_after_five_attempts() {
  Session s;
  s.go(settings("incoming", "manual"));
  s.engine.on_transport_closed("gateway_unreachable", "reset");
  for (int attempt = 1; attempt <= 5; attempt++) {
    CHECK(str(s.events.back(), "state") == "degraded");
    CHECK(str(s.events.back(), "message") ==
          "Connection lost — reconnecting (attempt " + std::to_string(attempt) + " of 5)");
    // Each wait is the back-off (0.5 s doubling, at most 8 s) shortened by up to half.
    const std::uint64_t whole = std::min<std::uint64_t>(8'000'000, 500'000ULL << (attempt - 1));
    const int before = s.host.connects;
    s.host.now += whole / 2 - 1'000;
    s.engine.tick();
    CHECK(s.host.connects == before);
    s.host.now += whole / 2 + 1'000;
    s.engine.tick();
    CHECK(s.host.connects == before + 1);
    s.engine.on_transport_closed("gateway_unreachable", "no route to host");  // the retry failed as well
  }
  CHECK(s.events.size() == 5 + 3);
  CHECK(same(s.events[5],
             R"({"type":"error","code":"gateway_unreachable","fatal":true,)"
             R"("message":"connection lost and could not be restored: no route to host"})"));
  CHECK(str(s.events[6], "state") == "stopping");
  CHECK(same(s.events[7], kIdleState));
  CHECK(s.host.connects == 6 && s.host.closes == 6 && !s.host.connected && s.host.nothing_open());
  s.host.now += 60'000'000;
  s.engine.tick();
  CHECK(s.host.connects == 6);

  // Stopping while a retry is pending cancels it.
  Session t;
  t.go(settings("incoming", "manual"));
  t.engine.on_transport_closed("gateway_unreachable", "reset");
  t.forget();
  t.engine.stop();
  CHECK(t.events.size() == 2 && same(t.events[1], kIdleState));
  // The connection is closed already; only the devices are left to release.
  CHECK(logged(t.host, {"flush:in", "close_mic", "close_source", "close_sink:in"}));
  t.host.now += 60'000'000;
  t.engine.tick();
  CHECK(t.host.connects == 1 && t.host.closes == 1);
}

static void test_reconnect_uses_the_token_from_update_access_token() {
  Json map = connected_by("account");
  map.set("accessToken", "old-access");
  Session s;
  s.go(map);
  CHECK(s.host.request.bearer == "old-access");

  // A new token changes nothing on the open connection; the next one sends it.
  s.engine.update_access_token("new-access");
  s.engine.update_access_token("");  // an empty token is ignored
  CHECK(s.events.empty() && s.host.log.empty() && s.host.connects == 1);
  s.engine.on_transport_closed("gateway_unreachable", "reset");
  s.host.now += 500'000;
  s.engine.tick();
  CHECK(s.host.connects == 2 && s.host.request.bearer == "new-access");
  Json body;
  CHECK(Json::parse(s.host.request.body, body) && same(body, R"({"mode":"account"})"));

  // One that arrives while the session waits to reconnect is used by that reconnect.
  s.engine.on_transport_open();
  s.ready(true, true);
  s.engine.on_transport_closed("gateway_unreachable", "reset");
  s.engine.update_access_token("newer-access");
  s.host.now += 500'000;
  s.engine.tick();
  CHECK(s.host.connects == 3 && s.host.request.bearer == "newer-access");

  // With no session it does nothing, and it never outlives the session it was given to.
  Session t;
  t.engine.update_access_token("stray-access");
  CHECK(t.events.empty() && t.host.log.empty());
  CHECK(t.engine.start(map));
  CHECK(t.host.request.bearer == "old-access");
  t.engine.update_access_token("later-access");
  t.engine.stop();
  CHECK(t.engine.start(map));
  CHECK(t.host.request.bearer == "old-access");
}

/// A session that lost its connection and is retrying it right now; whatever happened so far is forgotten.
static void reconnecting(Session& s, const Json& map) {
  s.go(map);
  s.engine.on_transport_closed("gateway_unreachable", "reset");
  s.host.now += 500'000;
  s.engine.tick();
  CHECK(s.host.connects == 2 && s.host.connected);
  s.forget();
}

static void test_terminal_refusals_during_reconnect_end_the_session() {
  // The gateway refused the credential or the account: no retry can change that, so it is said at once.
  for (const char* code : {"unauthorized", "invalid_token", "balance_empty", "billing_unavailable",
                           "accounts_unavailable", "bad_request"}) {
    Session s;
    reconnecting(s, connected_by("account", "incoming"));
    s.engine.on_transport_closed(code, std::string("the gateway refused the session (") + code + ")");
    CHECK(s.events.size() == 3);
    CHECK(str(s.events[0], "type") == "error" && str(s.events[0], "code") == code && yes(s.events[0], "fatal"));
    CHECK(str(s.events[0], "message") == std::string("the gateway refused the session (") + code + ")");
    CHECK(s.events.size() == 3 && str(s.events[1], "state") == "stopping" && same(s.events[2], kIdleState));
    CHECK(s.host.closes == 2 && !s.host.connected && s.host.nothing_open());
    s.host.now += 60'000'000;
    s.engine.tick();
    CHECK(s.host.connects == 2);
  }

  // A busy or failing gateway, or none at all, is retried as before.
  for (const char* code : {"session_limit", "rate_limited", "gateway_error", "gateway_unreachable"}) {
    Session s;
    reconnecting(s, connected_by("account", "incoming"));
    s.engine.on_transport_closed(code, "try again later");
    CHECK(s.events.size() == 1 && str(s.events[0], "state") == "degraded");
    CHECK(s.events.size() == 1 && str(s.events[0], "message") == "Connection lost — reconnecting (attempt 2 of 5)");
    CHECK(s.host.mic_open && s.host.source_open);
    s.host.now += 1'000'000;
    s.engine.tick();
    CHECK(s.host.connects == 3);
  }

  // The same holds in the other modes: a static token the gateway no longer accepts is not retried either.
  Session t;
  reconnecting(t, settings("captions", "manual"));
  t.engine.on_transport_closed("unauthorized", "the gateway rejected the access token");
  CHECK(t.events.size() == 3 && str(t.events[0], "code") == "unauthorized" && same(t.events[2], kIdleState));

  // A connection that had opened and then dropped is a lost connection, whatever code came with it.
  Session d;
  d.go(connected_by("account"));
  d.engine.on_transport_closed("unauthorized", "dropped");
  CHECK(d.events.size() == 1 && str(d.events[0], "state") == "degraded");
}

// ── Echo hold ──

static void test_echo_hold_in_automatic_modes() {
  Session s;
  s.go(settings("incoming", "vad"));
  FakeHost::Sink& in = s.host.sinks[1];
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 1);

  // While translated speech plays in the room the microphone is not forwarded, or it would be translated back.
  s.synthesized(kIn, 1, 1, 960, true);
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 1);
  s.source(kFrame);  // the meeting's own lane is not held
  CHECK(s.host.frames.size() == 2 && s.host.frames[1].direction == kIn);

  // ...and for 400 ms after it stopped.
  in.consumed = in.written;
  s.host.now += 399'999;
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 2);
  s.host.now += 1;
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 3 && s.host.frames[2].direction == kOut);
  CHECK(s.host.frames[2].sequence == 1);  // held frames were never numbered: the gateway sees no gap

  // Muted headphones cannot echo.
  s.engine.set_incoming_audio_muted(true);
  s.synthesized(kIn, 1, 2, 960, true);
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 4);
  s.engine.set_incoming_audio_muted(false);
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 4);

  // Push-to-talk is the user's own decision and is never held back.
  Session p;
  p.go(settings("incoming", "manual"));
  p.engine.ptt_down();
  p.synthesized(kIn, 1, 1, 960, true);
  p.mic(kFrame);
  CHECK(p.host.frames.size() == 1 && p.host.frames[0].direction == kOut);
}

// ── Sources and devices going away ──

static void test_source_and_device_loss() {
  Session s;
  s.go(settings("incoming", "vad"));
  s.host.source_is_alive = false;  // the meeting app quit
  s.host.now += 900'000;
  s.engine.tick();
  CHECK(s.host.source_alive_calls == 0 && s.events.empty());  // looked at once a second, not on every tick
  s.host.now += 100'000;
  s.engine.tick();
  CHECK(s.host.source_alive_calls == 1 && !s.host.source_open);
  CHECK(s.host.sent.size() == 1 && same(s.host.sent[0], R"({"v":1,"type":"capture.stop","direction":"in"})"));
  CHECK(s.events.size() == 2);
  CHECK(same(s.events[0],
             R"({"type":"error","code":"source_gone","direction":"in","fatal":false,)"
             R"("message":"the meeting app quit; incoming translation is off until you restart the session"})"));
  CHECK(str(s.events[1], "state") == "active" && !yes(s.events[1], "inReady") && yes(s.events[1], "outReady"));
  s.host.now += 3'000'000;
  s.engine.tick();
  CHECK(s.events.size() == 2 && s.host.source_alive_calls == 1);  // said once
  s.source(kFrame);
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 1 && s.host.frames[0].direction == kOut);  // the owner's side goes on

  // A device change that does not touch this session is only passed on.
  s.forget();
  s.engine.on_devices_changed();
  CHECK(s.events.size() == 1 && same(s.events[0], R"({"type":"devicesChanged"})"));

  // A device in use disappeared: the session stops instead of re-routing by itself.
  s.forget();
  s.host.devices.erase("phones");
  s.engine.on_devices_changed();
  CHECK(s.events.size() == 4 && str(s.events[0], "type") == "devicesChanged");
  CHECK(same(s.events[1],
             R"({"type":"error","code":"device_removed","fatal":true,)"
             R"("message":"an audio device in use was disconnected; the session was stopped"})"));
  CHECK(str(s.events[2], "state") == "stopping" && same(s.events[3], kIdleState));
  CHECK(!s.host.connected && s.host.nothing_open());
  s.forget();
  s.engine.on_devices_changed();
  CHECK(s.events.size() == 1);

  // Only devices the session really uses count: captions play nothing.
  Session c;
  c.go(settings("captions", "manual"));
  c.host.devices.erase("phones");
  c.host.devices.erase("cable");
  c.engine.on_devices_changed();
  CHECK(c.events.size() == 1 && c.host.connected);
  c.host.devices.erase("mic");
  c.engine.on_devices_changed();
  CHECK(c.events.size() == 5 && str(c.events[2], "code") == "device_removed" && !c.host.connected);

  Session b;
  b.go(settings("bidirectional", "manual", false));
  b.host.devices.erase("cable");
  b.engine.on_devices_changed();
  CHECK(b.events.size() == 4 && str(b.events[1], "code") == "device_removed");
}

// ── Queues that overflow ──

static void test_backlog_and_playback_overflow() {
  Session s;
  s.go(settings("bidirectional", "manual"));
  s.engine.ptt_down();
  s.forget();

  // The network does not keep up: frames are dropped, and the user is told at most once a second.
  s.host.network_keeps_up = false;
  s.mic(3 * kFrame);
  CHECK(s.host.frames.empty() && s.events.size() == 1);
  CHECK(same(s.events[0],
             R"({"type":"error","code":"capture_backlog","direction":"out","fatal":false,)"
             R"("message":"the network is not keeping up; some captured audio was dropped"})"));
  s.host.now += 1'000'001;
  s.mic(kFrame);
  CHECK(s.events.size() == 2);
  s.host.network_keeps_up = true;
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 1 && s.host.frames[0].sequence == 4);  // dropped frames keep their numbers

  // The playback queue is full: the turn is dropped here and cancelled on the gateway.
  s.forget();
  FakeHost::Sink& in = s.host.sinks[1];
  in.full = true;
  s.synthesized(kIn, 1, 1, 960, false);
  CHECK(s.events.size() == 1);
  CHECK(same(s.events[0],
             R"({"type":"error","code":"playback_overflow","direction":"in","fatal":false,)"
             R"("message":"translated audio queue is full; this turn was dropped"})"));
  CHECK(logged(s.host, {"flush:in", "turn.cancel"}));
  CHECK(same(s.host.sent[0], R"({"v":1,"type":"turn.cancel","direction":"in","generation":2})"));
  in.full = false;
  s.synthesized(kIn, 1, 1, 960, true);  // the rest of that turn
  in.consumed = in.written + 1;
  s.engine.tick();
  CHECK(in.writes.empty() && s.host.sent.size() == 1);
  s.source(kFrame);  // the lane itself stays open, in the new generation
  CHECK(s.host.frames.size() == 1 && s.host.frames[0].generation == 2 && s.host.frames[0].sequence == 0);
}

// ── Stop ──

static void test_stop_releases_everything() {
  Session s;
  s.go(settings("bidirectional", "vad"));
  s.engine.set_outgoing_muted(true);
  s.engine.set_incoming_audio_muted(true);
  s.mic(100);  // less than a frame: it waits for more
  s.forget();

  s.engine.stop();
  CHECK(s.events.size() == 2);
  CHECK(str(s.events[0], "state") == "stopping" && str(s.events[0], "mode") == "bidirectional");
  CHECK(yes(s.events[0], "outgoingMuted"));
  CHECK(same(s.events[1], kIdleState));  // the mutes belong to the session and end with it
  CHECK(logged(s.host,
               {"flush:out", "flush:in", "close", "close_mic", "close_source", "close_sink:out", "close_sink:in"}));
  CHECK(!s.host.connected && s.host.closes == 1 && s.host.nothing_open());

  // Nothing happens afterwards, whatever still arrives.
  s.forget();
  s.host.now += 5'000'000;
  s.engine.tick();
  s.mic(kFrame);
  s.source(kFrame);
  s.ready(true, true);
  s.caption("caption.final", "out", 1, 3);
  s.caption("caption.final", "in", 1, 2);
  s.synthesized(kOut, 3, 1, 960, true);
  s.engine.on_transport_closed("gateway_unreachable", "late");
  CHECK(s.events.empty() && s.host.log.empty());

  // Stop with no session only repeats the state.
  s.engine.stop();
  CHECK(s.events.size() == 1 && same(s.events[0], kIdleState));

  // The next session starts clean: audio the old one had not framed yet is not carried over.
  CHECK(s.engine.start(settings("captions", "vad", false)));
  s.engine.on_transport_open();
  s.ready(true, false);
  s.forget();
  const std::size_t fresh = s.mic_fed;
  s.mic(kFrame);
  CHECK(s.host.frames.size() == 1 && s.host.frames[0].payload.front() == recorded(fresh));
  CHECK(s.host.frames[0].generation == 3 && s.host.frames[0].sequence == 0);

  // Stopping before the connection opened closes it too.
  Session t;
  CHECK(t.engine.start(settings("captions", "manual")));
  t.engine.stop();
  CHECK(t.events.size() == 3 && same(t.events[2], kIdleState));
  CHECK(!t.host.connected && t.host.closes == 1 && t.host.nothing_open());
}

int main() {
  test_settings_are_validated();
  test_connection_modes_are_validated();
  test_session_request_per_connection_mode();
  test_session_refusals_pass_the_gateways_own_code();
  test_start_connects_and_configures_each_mode();
  test_unusable_routes_are_refused();
  test_first_connection_failure_ends_the_session();
  test_ready_reports_state_and_opens_capture();
  test_push_to_talk_turn();
  test_gateway_messages_become_bridge_events();
  test_account_balance_becomes_a_balance_event();
  test_synthesized_speech_is_played_and_reported();
  test_panic_discards_everything();
  test_outgoing_mute_cancels_the_turn_in_flight();
  test_bypass_routes_the_microphone_to_the_call();
  test_connection_loss_degrades_and_reconnects();
  test_reconnecting_gives_up_after_five_attempts();
  test_reconnect_uses_the_token_from_update_access_token();
  test_terminal_refusals_during_reconnect_end_the_session();
  test_echo_hold_in_automatic_modes();
  test_source_and_device_loss();
  test_backlog_and_playback_overflow();
  test_stop_releases_everything();
  return livebridge_test::finish();
}
