#include "livebridge/engine.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace livebridge {
namespace {

const int kMaxReconnectAttempts = 5;
/// Automatic turn modes: how long the microphone stays shut after translated incoming speech stopped playing.
const std::uint64_t kEchoTailUs = 400'000;
const std::uint64_t kBacklogWarningEveryUs = 1'000'000;
const std::uint64_t kSourceWatchEveryUs = 1'000'000;
const int kCaptureSampleRate = 16'000;
/// One capture frame: 20 ms of 16 kHz mono s16le.
const std::size_t kCaptureFrameBytes = 640;

const Direction kDirections[] = {Direction::out, Direction::in};

std::size_t slot(Direction direction) { return direction == Direction::out ? 0 : 1; }

Json object(std::initializer_list<Json::Object::value_type> members) { return Json(Json::Object(members)); }

const std::string* string_member(const Json& json, std::string_view key) {
  const Json* value = json.find(key);
  return value && value->is_string() ? &value->as_string() : nullptr;
}

bool flag(const Json* json, std::string_view key) {
  const Json* value = json ? json->find(key) : nullptr;
  return value && value->as_bool();
}

/// A JSON number is taken as an integer only when it is whole — what `as? Int` does in the Swift engine.
bool whole_number(const Json* value, long long& out) {
  if (!value || !value->is_number()) return false;
  const double number = value->as_number();
  if (number != std::floor(number) || std::fabs(number) >= 9.007199254740992e15) return false;
  out = static_cast<long long>(number);
  return true;
}

bool is_language_code(const std::string& code) {
  return code.size() >= 2 && code.size() <= 3 &&
         std::all_of(code.begin(), code.end(), [](char c) { return c >= 'a' && c <= 'z'; });
}

/// The shape of a provider voice id (`VOICE_ID_PATTERN` in packages/protocol): 10 to 40 ASCII letters and digits.
bool is_voice_id(const std::string& id) {
  return id.size() >= 10 && id.size() <= 40 && std::all_of(id.begin(), id.end(), [](char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
  });
}

bool is_http_url(const std::string& url) {
  if (std::any_of(url.begin(), url.end(), [](char c) { return static_cast<unsigned char>(c) <= 0x20; })) return false;
  for (const std::string_view scheme : {std::string_view("http://"), std::string_view("https://")})
    if (url.size() > scheme.size() && url.compare(0, scheme.size(), scheme) == 0) return true;
  return false;
}

const char* mode_name(EngineConfig::Mode mode) {
  switch (mode) {
    case EngineConfig::Mode::captions: return "captions";
    case EngineConfig::Mode::incoming: return "incoming";
    case EngineConfig::Mode::bidirectional: return "bidirectional";
  }
  return "captions";
}

bool mode_from_name(const std::string& name, EngineConfig::Mode& mode) {
  for (const EngineConfig::Mode candidate :
       {EngineConfig::Mode::captions, EngineConfig::Mode::incoming, EngineConfig::Mode::bidirectional}) {
    if (name == mode_name(candidate)) {
      mode = candidate;
      return true;
    }
  }
  return false;
}

bool connection_from_name(const std::string& name, EngineConfig::Connection& connection) {
  if (name == "token") connection = EngineConfig::Connection::token;
  else if (name == "account") connection = EngineConfig::Connection::account;
  else if (name == "keys") connection = EngineConfig::Connection::keys;
  else return false;
  return true;
}

bool one_of(std::string_view code, std::initializer_list<const char*> codes) {
  return std::any_of(codes.begin(), codes.end(), [code](const char* each) { return code == std::string_view(each); });
}

/// The gateway's own refusal codes that the app tells the user about; anything else is a plain `gateway_error`.
bool is_refusal_code(std::string_view code) {
  return one_of(code, {"unauthorized", "invalid_token", "balance_empty", "session_limit", "rate_limited",
                       "billing_unavailable", "accounts_unavailable", "bad_request"});
}

/// The gateway refused this credential or account: retrying the same request cannot succeed.
bool is_terminal_refusal(std::string_view code) {
  return one_of(code, {"unauthorized", "invalid_token", "balance_empty", "billing_unavailable",
                       "accounts_unavailable", "bad_request"});
}

/// The wait before reconnect attempt `attempt`: 0.5 s doubling up to 8 s, then shortened by up to half so that
/// clients which lost the same gateway do not all come back in the same instant. The spread is derived from `seed`
/// (the clock at the moment of the drop), which keeps the engine free of hidden state and its tests exact.
std::uint64_t reconnect_delay_us(int attempt, std::uint64_t seed) {
  const double base_seconds = std::min(8.0, 0.5 * std::pow(2.0, attempt - 1));
  std::uint64_t mixed = seed + 0x9E3779B97F4A7C15ULL;  // one splitmix64 step
  mixed = (mixed ^ (mixed >> 30)) * 0xBF58476D1CE4E5B9ULL;
  mixed = (mixed ^ (mixed >> 27)) * 0x94D049BB133111EBULL;
  mixed ^= mixed >> 31;
  const double spread = 0.5 + 0.5 * (static_cast<double>(mixed >> 11) / 9007199254740992.0);  // [0.5, 1)
  return static_cast<std::uint64_t>(base_seconds * spread * 1e6);
}

bool refuse(HostError& error, const char* code, const char* message) {
  error.code = code;
  error.message = message;
  return false;
}

}  // namespace

bool EngineConfig::parse(const Json& settings, EngineConfig& out) {
  const std::string* url = string_member(settings, "gatewayUrl");
  const std::string* token = string_member(settings, "accessToken");
  const std::string* mic = string_member(settings, "micUid");
  const std::string* headphones = string_member(settings, "headphonesUid");
  const std::string* target = string_member(settings, "targetLang");
  const std::string* my = string_member(settings, "myLang");
  const std::string* mode = string_member(settings, "mode");
  const std::string* commit = string_member(settings, "outCommit");

  EngineConfig config;
  if (!url || !is_http_url(*url) || !mic || !headphones) return false;
  // Absent means the user's own gateway; a value that is there must name one of the modes.
  if (const Json* wire = settings.find("connection");
      wire && !(wire->is_string() && connection_from_name(wire->as_string(), config.connection)))
    return false;
  if (token) config.access_token = *token;
  if (const std::string* key = string_member(settings, "elevenlabsApiKey")) config.elevenlabs_api_key = *key;
  if (const std::string* key = string_member(settings, "geminiApiKey")) config.gemini_api_key = *key;
  // Keys mode pays with the user's own provider keys; the other two modes need the access token.
  if (config.connection == Connection::keys ? config.elevenlabs_api_key.empty() || config.gemini_api_key.empty()
                                            : config.access_token.empty())
    return false;
  if (!target || !is_language_code(*target)) return false;
  config.my_lang = my ? *my : "uz";
  if (!is_language_code(config.my_lang) || config.my_lang == *target) return false;
  if (!mode || !mode_from_name(*mode, config.mode)) return false;
  if (!commit || (*commit != "manual" && *commit != "vad" && *commit != "turn_prediction")) return false;

  config.gateway_url = *url;
  config.mic_uid = *mic;
  config.headphones_uid = *headphones;
  if (const std::string* virtual_mic = string_member(settings, "virtualMicUid")) config.virtual_mic_uid = *virtual_mic;
  if (const Json* pids = settings.find("sourcePids")) {
    for (const Json& pid : pids->as_array()) {
      const double number = pid.as_number(-1);
      if (pid.is_number() && number >= 0 && number <= 2147483647.0)
        config.source_pids.push_back(static_cast<int>(number));
    }
  }
  config.target_lang = *target;
  config.out_commit = *commit;
  if (const std::string* model = string_member(settings, "translationModel")) config.translation_model = *model;
  // A voice id that is not well-formed is dropped rather than refused: the session then speaks in the default voice.
  if (const std::string* voice = string_member(settings, "outVoiceId"); voice && is_voice_id(*voice))
    config.out_voice_id = *voice;
  if (const std::string* voice = string_member(settings, "inVoiceId"); voice && is_voice_id(*voice))
    config.in_voice_id = *voice;
  out = std::move(config);
  return true;
}

SessionRequest session_request(const EngineConfig& config) {
  SessionRequest request;
  switch (config.connection) {
    case EngineConfig::Connection::token:
      request.bearer = config.access_token;
      break;
    case EngineConfig::Connection::account:
      request.bearer = config.access_token;
      request.body = object({{"mode", "account"}}).dump();
      break;
    case EngineConfig::Connection::keys:
      request.body = object({{"mode", "keys"},
                             {"elevenlabs_api_key", config.elevenlabs_api_key},
                             {"gemini_api_key", config.gemini_api_key}})
                         .dump();
      break;
  }
  return request;
}

HostError session_refusal(unsigned long status, std::string_view body) {
  Json answer;
  if (Json::parse(body, answer)) {
    const std::string* code = string_member(answer, "error");
    if (code && is_refusal_code(*code)) return {*code, "the gateway refused the session (" + *code + ")"};
  }
  // Older gateways answer without a body.
  if (status == 401) return {"unauthorized", "the gateway rejected the access token"};
  if (status == 429) return {"session_limit", "the gateway already has an active session"};
  return {"gateway_error", "gateway answered HTTP " + std::to_string(status)};
}

Engine::Engine(EngineHost& host, EventCallback on_event) : host_(host), on_event_(std::move(on_event)) {}

// ── Commands ──

bool Engine::start(const Json& settings) {
  EngineConfig config;
  if (!EngineConfig::parse(settings, config)) return false;
  start_session(std::move(config));
  return true;
}

void Engine::stop() { stop_session(nullptr); }

void Engine::update_access_token(const std::string& token) {
  if (config_ && !token.empty()) config_->access_token = token;
}

void Engine::ptt_down() {
  if (!config_ || config_->out_commit != "manual") return;
  if (phase_ != Phase::ready && phase_ != Phase::active) return;
  if (!direction_ready_[0] || outgoing_muted_ || bypass_ || ptt_held_) return;
  ptt_held_ = true;
  send("capture.start", {{"direction", "out"}, {"generation", static_cast<long long>(generation_[0])}});
  emit_state();
}

void Engine::ptt_up() {
  if (!config_ || config_->out_commit != "manual" || !ptt_held_) return;
  release_push_to_talk();
  emit_state();
}

void Engine::set_out_commit(const std::string& commit) {
  if (commit != "manual" && commit != "vad" && commit != "turn_prediction") return;
  if (!config_ || commit == config_->out_commit) return;
  // Reconnects send it in `session.configure`; the open connection is told by `sync_out_commit`.
  config_->out_commit = commit;
  sync_out_commit();
  emit_state();
}

void Engine::set_outgoing_muted(bool muted) {
  outgoing_muted_ = muted;
  if (muted) {
    ptt_held_ = false;
    if (phase_ != Phase::idle) cancel(Direction::out);
  }
  open_hands_free_capture_if_needed();
  emit_state();
}

void Engine::set_incoming_audio_muted(bool muted) {
  incoming_audio_muted_ = muted;
  if (sink_open_[1]) {
    host_.sink_set_muted(Direction::in, muted);
    sink_muted_[1] = muted;
  }
  emit_state();
}

void Engine::set_bypass(bool enabled) {
  if (enabled == bypass_) return;
  if (enabled) {
    if (!sink_open_[0]) {
      emit_error("no_virtual_mic", "bypass needs the virtual microphone", false);
      return;
    }
    // Translated speech stops; from here the physical microphone goes to the call directly, with no server.
    ptt_held_ = false;
    cancel(Direction::out);
    bypass_ = true;
  } else {
    bypass_ = false;
    if (sink_open_[0]) host_.sink_flush(Direction::out);
    open_hands_free_capture_if_needed();
  }
  emit_state();
}

void Engine::panic() {
  // Silence first — before any teardown work — so nothing already queued is heard.
  for (const Direction direction : kDirections) {
    if (!sink_open_[slot(direction)]) continue;
    host_.sink_set_muted(direction, true);
    sink_muted_[slot(direction)] = true;
    host_.sink_flush(direction);
  }
  stop_session("Panic stop: all audio discarded");
}

// ── Session lifecycle ──

void Engine::start_session(EngineConfig config) {
  if (phase_ != Phase::idle) {
    emit_error("busy", "a session is already running", false);
    return;
  }
  HostError error;
  if (!open_audio(config, error)) {
    release_audio();
    emit_error(error.code.empty() ? "error" : error.code, error.message, true);
    return;
  }
  config_ = std::move(config);
  phase_ = Phase::connecting;
  status_message_.reset();
  reconnect_attempt_ = 0;
  last_source_watch_us_ = host_.now_us();
  emit_state();
  connect();
}

/// Checks the whole route first, then opens the sinks, the microphone and the meeting source. On failure the
/// caller closes whatever was opened.
bool Engine::open_audio(const EngineConfig& config, HostError& error) {
  // The same device must never be both where translated speech is written and where anything is captured or
  // monitored, or the call would hear itself.
  if (config.virtual_mic_uid) {
    if (*config.virtual_mic_uid == config.mic_uid)
      return refuse(error, "unsafe_route", "The virtual microphone cannot also be the capture microphone.");
    if (*config.virtual_mic_uid == config.headphones_uid)
      return refuse(error, "unsafe_route",
                    "Incoming audio cannot be played into the virtual microphone — the call would hear it.");
  }
  const bool incoming_enabled = !config.source_pids.empty();
  const bool speak_out = config.mode == EngineConfig::Mode::bidirectional;
  const bool speak_in = config.mode != EngineConfig::Mode::captions && incoming_enabled;

  DeviceInfo virtual_mic, headphones, microphone;
  if (speak_out && !(config.virtual_mic_uid && host_.find_device(*config.virtual_mic_uid, virtual_mic) &&
                     virtual_mic.output_channels > 0))
    return refuse(error, "no_virtual_mic", "bidirectional speech needs the virtual microphone");
  if (speak_in && !(host_.find_device(config.headphones_uid, headphones) && headphones.output_channels > 0 &&
                    !headphones.is_virtual))
    return refuse(error, "no_headphones", "choose a physical output device for incoming audio");
  if (!(host_.find_device(config.mic_uid, microphone) && microphone.input_channels > 0))
    return refuse(error, "no_microphone", "the selected microphone is not available");

  // `error` is preset before each call, so a host that only answers "no" still produces a usable error event.
  if (speak_out) {
    error = {"device", "cannot open the virtual microphone device"};
    if (!host_.open_sink(Direction::out, *config.virtual_mic_uid, error)) return false;
    sink_open_[0] = true;
  }
  if (speak_in) {
    error = {"device", "cannot open the output device for incoming audio"};
    if (!host_.open_sink(Direction::in, config.headphones_uid, error)) return false;
    sink_open_[1] = true;
  }
  error = {"device", "cannot open the microphone"};
  if (!host_.open_microphone(config.mic_uid, error)) return false;
  mic_open_ = true;
  if (incoming_enabled) {
    error = {"source_gone", "cannot capture the meeting app; pick it again"};
    if (!host_.open_source(config.source_pids, error)) return false;
    source_open_ = true;
  }
  return true;
}

void Engine::connect() {
  if (!config_) return;
  transport_active_ = true;
  transport_open_ = false;
  host_.connect(config_->gateway_url, session_request(*config_));
}

void Engine::close_transport() {
  if (!transport_active_) return;
  transport_active_ = false;
  transport_open_ = false;
  // What the gateway announced and runs belongs to that connection.
  session_ready_ = false;
  gateway_features_.clear();
  gateway_out_commit_.reset();
  host_.close();
}

void Engine::connection_lost(const std::string& reason) {
  if (phase_ == Phase::idle || phase_ == Phase::stopping) return;
  close_transport();
  // Nothing captured or synthesized before the drop may be replayed after it.
  fence_all();
  direction_ready_[0] = direction_ready_[1] = false;
  in_capture_started_ = false;
  out_capture_open_ = false;
  ptt_held_ = false;
  reconnect_attempt_++;
  if (reconnect_attempt_ > kMaxReconnectAttempts) {
    emit_error("gateway_unreachable", "connection lost and could not be restored: " + reason, true);
    stop_session(nullptr);
    return;
  }
  phase_ = Phase::degraded;
  status_message_ = "Connection lost — reconnecting (attempt " + std::to_string(reconnect_attempt_) + " of " +
                    std::to_string(kMaxReconnectAttempts) + ")";
  emit_state();
  const std::uint64_t now = host_.now_us();
  reconnect_at_us_ = now + reconnect_delay_us(reconnect_attempt_, now);
}

void Engine::stop_session(const char* message) {
  if (phase_ == Phase::idle) {
    if (message) status_message_ = message;
    emit_state();
    return;
  }
  phase_ = Phase::stopping;
  emit_state();
  fence_all();
  close_transport();
  release_audio();
  config_.reset();
  direction_ready_[0] = direction_ready_[1] = false;
  in_capture_started_ = false;
  out_capture_open_ = false;
  ptt_held_ = false;
  outgoing_muted_ = false;
  incoming_audio_muted_ = false;
  bypass_ = false;
  mock_ = false;
  phase_ = Phase::idle;
  if (message) status_message_ = message;
  else status_message_.reset();
  emit_state();
}

/// Closes every device this session opened. After this the virtual microphone carries silence.
void Engine::release_audio() {
  if (mic_open_) host_.close_microphone();
  mic_open_ = false;
  if (source_open_) host_.close_source();
  source_open_ = false;
  for (const Direction direction : kDirections) {
    const std::size_t i = slot(direction);
    if (sink_open_[i]) host_.close_sink(direction);
    sink_open_[i] = false;
    sink_muted_[i] = false;
    pending_capture_[i].clear();
  }
}

/// Moves both directions to a new generation and empties both playback queues.
void Engine::fence_all() {
  for (const Direction direction : kDirections) {
    const std::size_t i = slot(direction);
    generation_[i]++;
    capture_sequence_[i] = 0;
    playing_[i].clear();
    if (sink_open_[i]) host_.sink_flush(direction);
    turn_base_[i] = highest_turn_[i];
  }
  released_at_us_.reset();
  end_to_end_ms_.clear();
}

/// Cancels whatever is in flight for one direction, locally and on the gateway.
void Engine::cancel(Direction direction) {
  const std::size_t i = slot(direction);
  generation_[i]++;
  capture_sequence_[i] = 0;
  playing_[i].clear();
  if (sink_open_[i]) host_.sink_flush(direction);
  if (direction == Direction::out) {
    released_at_us_.reset();
    out_capture_open_ = false;
  }
  send("turn.cancel",
       {{"direction", direction_name(direction)}, {"generation", static_cast<long long>(generation_[i])}});
}

/// The talk button let go: the phrase is committed and the outgoing lane paused.
void Engine::release_push_to_talk() {
  ptt_held_ = false;
  // Frames are sent in order on the same socket, so the commit always follows the last captured frame.
  send("turn.commit", {{"direction", "out"}});
  send("capture.pause", {{"direction", "out"}});
  released_at_us_ = host_.now_us();
}

/// Tells a ready gateway the session's outgoing turn mode when the mode it runs is a different one. A gateway that
/// cannot switch during a session keeps its mode, and so does the session.
void Engine::sync_out_commit() {
  if (!config_ || !session_ready_ || !gateway_out_commit_ || *gateway_out_commit_ == config_->out_commit) return;
  // Leaving push-to-talk while the button is held is a release, even on a gateway that cannot switch: the app has let
  // go of the button already, so nothing else would end the turn.
  if (*gateway_out_commit_ == "manual" && ptt_held_) release_push_to_talk();
  if (std::find(gateway_features_.begin(), gateway_features_.end(), "turn.mode") == gateway_features_.end()) {
    config_->out_commit = *gateway_out_commit_;
    // The state showing the mode in force comes first, so that the app can go back to it when the error arrives.
    emit_state();
    emit_error("mode_switch_unsupported",
               "This gateway cannot change the turn mode during a session; stop and start again to use the new mode",
               false, "out");
    return;
  }
  // Entering push-to-talk closes the hands-free lane; what was being said, the gateway commits.
  if (config_->out_commit == "manual" && out_capture_open_) {
    out_capture_open_ = false;
    send("capture.pause", {{"direction", "out"}});
  }
  send("turn.mode", {{"direction", "out"}, {"commit", config_->out_commit}});
  gateway_out_commit_ = config_->out_commit;
  open_hands_free_capture_if_needed();
  if (phase_ == Phase::ready || phase_ == Phase::active)
    phase_ = in_capture_started_ || out_capture_open_ ? Phase::active : Phase::ready;
}

/// In the automatic turn modes the outgoing capture window is open whenever it is allowed to be.
void Engine::open_hands_free_capture_if_needed() {
  if (!config_ || config_->out_commit == "manual" || out_capture_open_) return;
  if (!direction_ready_[0] || outgoing_muted_ || bypass_) return;
  out_capture_open_ = true;
  send("capture.start", {{"direction", "out"}, {"generation", static_cast<long long>(generation_[0])}});
}

long long Engine::display_turn(Direction direction, long long gateway_turn) {
  const std::size_t i = slot(direction);
  const long long id = turn_base_[i] + gateway_turn;
  highest_turn_[i] = std::max(highest_turn_[i], id);
  return id;
}

// ── Capture -> gateway ──

void Engine::on_captured(Direction direction, const std::uint8_t* pcm, std::size_t bytes) {
  if (!(direction == Direction::out ? mic_open_ : source_open_) || !pcm || bytes == 0) return;
  std::vector<std::uint8_t>& pending = pending_capture_[slot(direction)];
  pending.insert(pending.end(), pcm, pcm + bytes);
  std::size_t used = 0;
  for (; pending.size() - used >= kCaptureFrameBytes; used += kCaptureFrameBytes)
    capture_frame(direction, pending.data() + used);
  pending.erase(pending.begin(), pending.begin() + static_cast<std::ptrdiff_t>(used));
}

/// One 20 ms frame: to the gateway if its lane is open right now, into the virtual microphone under bypass,
/// nowhere otherwise.
void Engine::capture_frame(Direction direction, const std::uint8_t* pcm) {
  if (phase_ != Phase::ready && phase_ != Phase::active) return;
  const std::size_t i = slot(direction);
  if (direction == Direction::out) {
    if (bypass_) {
      if (sink_open_[0]) host_.sink_write(Direction::out, pcm, kCaptureFrameBytes, kCaptureSampleRate);
      return;
    }
    // Nothing leaves the machine unless the talk button is held (or an automatic turn mode is open).
    if (!(ptt_held_ || out_capture_open_) || outgoing_muted_ || !direction_ready_[0]) return;
    if (out_capture_open_ && !ptt_held_) {
      const std::uint64_t now = host_.now_us();
      if (sink_open_[1] && !sink_muted_[1] && host_.sink_written(Direction::in) > host_.sink_consumed(Direction::in))
        echo_hold_until_us_ = now + kEchoTailUs;
      if (now < echo_hold_until_us_) return;
    }
  } else if (!in_capture_started_ || !direction_ready_[1]) {
    return;
  }

  AudioFrame frame;
  frame.kind = AudioFrame::Kind::capture;
  frame.direction = direction;
  frame.generation = generation_[i];
  frame.sequence = capture_sequence_[i]++;
  frame.timestamp_us = host_.now_us();
  frame.payload.assign(pcm, pcm + kCaptureFrameBytes);
  std::vector<std::uint8_t> encoded;
  if (encode_frame(frame, encoded) != FrameError::none || !transport_open_) return;
  if (host_.send_binary(encoded.data(), encoded.size())) return;
  const std::uint64_t now = host_.now_us();
  if (now - last_backlog_warning_us_ > kBacklogWarningEveryUs) {
    last_backlog_warning_us_ = now;
    emit_error("capture_backlog", "the network is not keeping up; some captured audio was dropped", false,
               direction_name(direction));
  }
}

// ── Gateway -> playback / interface ──

void Engine::on_transport_open() {
  if (!transport_active_ || transport_open_ || !config_) return;
  transport_open_ = true;
  const EngineConfig& config = *config_;
  const bool incoming_enabled = !config.source_pids.empty();
  Json::Object configure{
      {"v", 1},
      {"type", "session.configure"},
      {"capture_format", object({{"encoding", "pcm_s16le"}, {"sample_rate", kCaptureSampleRate}, {"channels", 1}})},
      {"directions",
       object({{"out", object({{"enabled", true},
                               {"source_lang", config.my_lang},
                               {"target_lang", config.target_lang},
                               {"speak", config.mode == EngineConfig::Mode::bidirectional},
                               {"commit", config.out_commit}})},
               {"in", object({{"enabled", incoming_enabled},
                              {"source_lang", config.target_lang},
                              {"target_lang", config.my_lang},
                              {"speak", config.mode != EngineConfig::Mode::captions},
                              {"commit", "vad"}})}})},
  };
  if (!config.translation_model.empty()) configure.emplace_back("translation_model", config.translation_model);
  Json::Object voices;
  if (!config.out_voice_id.empty()) voices.emplace_back("out", config.out_voice_id);
  if (!config.in_voice_id.empty()) voices.emplace_back("in", config.in_voice_id);
  if (!voices.empty()) configure.emplace_back("voices", Json(std::move(voices)));
  host_.send_text(Json(std::move(configure)).dump());
  gateway_out_commit_ = config.out_commit;
}

void Engine::on_transport_closed(std::string_view code, std::string_view reason) {
  if (!transport_active_) return;
  // First connection: fail loudly. Later ones are retries of a session that was already running; they keep
  // retrying unless the gateway refused the credential or the account, which is then said with its own code.
  if (!transport_open_ && (phase_ == Phase::connecting || is_terminal_refusal(code))) {
    emit_error(code.empty() ? "gateway_unreachable" : std::string(code), std::string(reason), true);
    stop_session(nullptr);
    return;
  }
  connection_lost(std::string(reason));
}

void Engine::on_transport_text(std::string_view text) {
  if (!transport_open_) return;
  Json message;
  if (Json::parse(text, message) && message.is_object()) received(message);
}

void Engine::received(const Json& message) {
  const std::string* type_member = string_member(message, "type");
  if (!type_member) return;
  const std::string& type = *type_member;
  Direction direction = Direction::out;
  const std::string* direction_member = string_member(message, "direction");
  const bool has_direction = direction_member && direction_from_name(*direction_member, direction);
  // Anything tagged with an older generation belongs to a cancelled turn.
  long long tagged = 0;
  if (has_direction && whole_number(message.find("generation"), tagged) && tagged != generation_[slot(direction)])
    return;
  long long turn_id = 0;
  whole_number(message.find("turn_id"), turn_id);

  if (type == "session.ready") {
    const Json* directions = message.find("directions");
    for (const Direction each : kDirections) {
      const Json* info = directions ? directions->find(direction_name(each)) : nullptr;
      direction_ready_[slot(each)] = flag(info, "enabled") && flag(info, "ready");
      long long rate = 0;
      if (info && whole_number(info->find("synth_sample_rate"), rate) && rate > 0 && rate <= 384'000)
        synth_rate_[slot(each)] = static_cast<int>(rate);
    }
    mock_ = flag(message.find("providers"), "mock");
    session_ready_ = true;
    gateway_features_.clear();
    if (const Json* features = message.find("features")) {
      for (const Json& feature : features->as_array())
        if (feature.is_string()) gateway_features_.push_back(feature.as_string());
    }
    reconnect_attempt_ = 0;
    status_message_.reset();
    if (direction_ready_[1] && !in_capture_started_) {
      in_capture_started_ = true;
      send("capture.start", {{"direction", "in"}, {"generation", static_cast<long long>(generation_[1])}});
    }
    // A switch the gateway cannot make is undone before the outgoing lane opens in the wrong mode.
    sync_out_commit();
    open_hands_free_capture_if_needed();
    phase_ = in_capture_started_ || out_capture_open_ ? Phase::active : Phase::ready;
    emit_state();
    return;
  }

  if (type == "error") {
    const bool fatal = flag(&message, "fatal");
    const std::string* code = string_member(message, "code");
    const std::string* text = string_member(message, "message");
    emit_error(code ? *code : "error", text ? *text : "", fatal, has_direction ? direction_name(direction) : nullptr);
    if (fatal) stop_session(nullptr);
    return;
  }

  if (type == "account.balance") {
    long long units = 0;
    if (whole_number(message.find("balance_units"), units))
      emit(object({{"type", "balance"}, {"balanceUnits", units}}));
    return;
  }

  if (!has_direction) return;
  const char* name = direction_name(direction);

  if (type == "metrics") {
    Json event = object({{"type", "metrics"}, {"direction", name}, {"turnId", display_turn(direction, turn_id)}});
    // Stages that did not run are absent from the gateway's message and stay absent here.
    static const char* const kStages[][2] = {
        {"stt_commit_ms", "sttCommitMs"},
        {"translate_first_ms", "translateFirstMs"},
        {"translate_total_ms", "translateTotalMs"},
        {"tts_first_audio_ms", "ttsFirstAudioMs"},
        {"tts_total_ms", "ttsTotalMs"},
        {"audio_ms", "audioMs"},
    };
    for (const auto& stage : kStages) {
      long long value = 0;
      if (whole_number(message.find(stage[0]), value)) event.set(stage[1], value);
    }
    if (const std::string* model = string_member(message, "model")) event.set("model", *model);
    if (direction == Direction::out && turn_id >= 0 && turn_id <= 0xFFFFFFFFLL) {
      const auto measured = end_to_end_ms_.find(static_cast<std::uint32_t>(turn_id));
      if (measured != end_to_end_ms_.end()) {
        event.set("e2eMs", measured->second);
        end_to_end_ms_.erase(measured);
      }
    }
    emit(event);
    return;
  }

  if (type == "turn.skipped") {
    // The turn's caption stays; it was not translated or spoken (same language, or our own speech coming back).
    const std::string* reason = string_member(message, "reason");
    emit(object({{"type", "caption"},
                 {"direction", name},
                 {"turnId", display_turn(direction, turn_id)},
                 {"kind", "skipped"},
                 {"text", ""},
                 {"reason", reason ? *reason : std::string()}}));
    return;
  }

  static const char* const kKinds[][2] = {
      {"caption.partial", "partial"},
      {"caption.final", "final"},
      {"translation.delta", "translationDelta"},
      {"translation.final", "translationFinal"},
  };
  for (const auto& kind : kKinds) {
    if (type != kind[0]) continue;
    const std::string* text = string_member(message, "text");
    emit(object({{"type", "caption"},
                 {"direction", name},
                 {"turnId", display_turn(direction, turn_id)},
                 {"kind", kind[1]},
                 {"text", text ? *text : std::string()}}));
    return;
  }
}

void Engine::on_transport_binary(const std::uint8_t* data, std::size_t size) {
  if (!transport_open_ || !data) return;
  AudioFrame frame;
  if (decode_frame(data, size, frame) != FrameError::none || frame.kind != AudioFrame::Kind::synthesized) return;
  const Direction direction = frame.direction;
  const std::size_t i = slot(direction);
  if (frame.generation != generation_[i] || !sink_open_[i]) return;
  // Muted or bypassed outgoing speech is discarded on arrival, never queued for later.
  if (direction == Direction::out && (outgoing_muted_ || bypass_)) return;

  std::vector<PlayingTurn>& turns = playing_[i];
  if (!frame.payload.empty()) {
    if (turns.empty() || turns.back().id != frame.turn_id) {
      PlayingTurn turn;
      turn.id = frame.turn_id;
      turn.start = host_.sink_written(direction);
      turns.push_back(turn);
    }
    if (!host_.sink_write(direction, frame.payload.data(), frame.payload.size(), synth_rate_[i])) {
      emit_error("playback_overflow", "translated audio queue is full; this turn was dropped", false,
                 direction_name(direction));
      cancel(direction);
      return;
    }
  }
  if (frame.is_end_of_turn()) {
    host_.sink_end_input(direction);
    const auto turn = std::find_if(turns.rbegin(), turns.rend(),
                                   [&](const PlayingTurn& playing) { return playing.id == frame.turn_id; });
    if (turn != turns.rend()) {
      turn->end = host_.sink_written(direction);
      turn->ended = true;
    }
  }
}

/// Reports when a turn actually becomes audible and when it has finished playing.
void Engine::observe_playback() {
  for (const Direction direction : kDirections) {
    const std::size_t i = slot(direction);
    std::vector<PlayingTurn>& turns = playing_[i];
    if (!sink_open_[i] || turns.empty()) continue;
    const std::int64_t consumed = host_.sink_consumed(direction);
    const char* name = direction_name(direction);
    const long long generation = generation_[i];

    for (PlayingTurn& turn : turns) {
      if (turn.started || consumed <= turn.start) continue;
      turn.started = true;
      send("playback.start",
           {{"direction", name}, {"turn_id", static_cast<long long>(turn.id)}, {"generation", generation}});
      if (direction == Direction::out && released_at_us_) {
        const long long ms = static_cast<long long>((host_.now_us() - *released_at_us_) / 1000);
        released_at_us_.reset();
        end_to_end_ms_[turn.id] = ms;
        // The gateway's metrics message for a turn usually arrives after its audio started; if it came first,
        // publish the client-side figure on its own.
        emit(object({{"type", "metrics"},
                     {"direction", "out"},
                     {"turnId", display_turn(direction, turn.id)},
                     {"e2eMs", ms}}));
      }
    }

    std::size_t kept = 0;
    for (const PlayingTurn& turn : turns) {
      if (turn.ended && consumed >= turn.end) {
        send("playback.end",
             {{"direction", name}, {"turn_id", static_cast<long long>(turn.id)}, {"generation", generation}});
      } else {
        turns[kept++] = turn;
      }
    }
    turns.erase(turns.begin() + static_cast<std::ptrdiff_t>(kept), turns.end());
  }
}

// ── Device and source supervision ──

void Engine::on_devices_changed() {
  emit(object({{"type", "devicesChanged"}}));
  if (!config_ || phase_ == Phase::idle || phase_ == Phase::stopping) return;
  const auto missing = [&](const std::string& uid) {
    DeviceInfo info;
    return !host_.find_device(uid, info);
  };
  const bool removed = missing(config_->mic_uid) || (sink_open_[1] && missing(config_->headphones_uid)) ||
                       (sink_open_[0] && config_->virtual_mic_uid && missing(*config_->virtual_mic_uid));
  if (!removed) return;
  // Never re-route silently to whatever the new default is: stop and let the user choose again.
  emit_error("device_removed", "an audio device in use was disconnected; the session was stopped", true);
  stop_session(nullptr);
}

void Engine::watch_source() {
  if (!source_open_ || host_.source_alive()) return;
  host_.close_source();
  source_open_ = false;
  pending_capture_[1].clear();
  direction_ready_[1] = false;
  if (in_capture_started_) send("capture.stop", {{"direction", "in"}});
  in_capture_started_ = false;
  emit_error("source_gone", "the meeting app quit; incoming translation is off until you restart the session", false,
             "in");
  emit_state();
}

void Engine::tick() {
  if (phase_ == Phase::idle) return;
  observe_playback();
  const std::uint64_t now = host_.now_us();
  if (now - last_source_watch_us_ >= kSourceWatchEveryUs) {
    last_source_watch_us_ = now;
    watch_source();
  }
  if (phase_ == Phase::degraded && !transport_active_ && now >= reconnect_at_us_) connect();
}

// ── Messages and events ──

void Engine::send(const char* type, Members fields) {
  if (!transport_open_) return;
  Json::Object message{{"v", 1}, {"type", type}};
  message.insert(message.end(), fields);
  host_.send_text(Json(std::move(message)).dump());
}

void Engine::emit(const Json& event) {
  if (on_event_) on_event_(event);
}

void Engine::emit_state() {
  static const char* const kPhases[] = {"idle", "connecting", "ready", "active", "degraded", "stopping"};
  Json event = object({
      {"type", "state"},
      {"state", kPhases[static_cast<int>(phase_)]},
      {"outReady", direction_ready_[0]},
      {"inReady", direction_ready_[1]},
      {"capturing", ptt_held_ || out_capture_open_ || in_capture_started_ || bypass_},
      {"mock", mock_},
      {"bypass", bypass_},
      {"outgoingMuted", outgoing_muted_},
      {"incomingAudioMuted", incoming_audio_muted_},
  });
  if (status_message_) event.set("message", *status_message_);
  if (config_) {
    // Session shape for the numbers-only analytics log (no device names, addresses or text).
    event.set("mode", mode_name(config_->mode));
    event.set("myLang", config_->my_lang);
    event.set("targetLang", config_->target_lang);
    event.set("outCommit", config_->out_commit);
  }
  emit(event);
}

void Engine::emit_error(const std::string& code, const std::string& message, bool fatal, const char* direction) {
  Json event = object({{"type", "error"}, {"code", code}, {"message", message}, {"fatal", fatal}});
  if (direction) event.set("direction", direction);
  emit(event);
}

}  // namespace livebridge
