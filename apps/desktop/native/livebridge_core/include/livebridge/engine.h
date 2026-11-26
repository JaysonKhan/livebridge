// The session logic of the audio engine with no platform code in it: the C++ twin of Engine.swift.
//
// `Engine` decides what to open, what to send to the gateway and what to tell the interface; the platform (WASAPI
// and WinHTTP on Windows, a fake in the tests) does the opening and sending behind `EngineHost`. Events are `Json`
// objects shaped per docs/bridge-contract.md.
//
// Threading: there is none in here. Every `Engine` method — the commands, the `on_*` host callbacks and `tick()` —
// is called on one thread, the host's engine thread. The engine never blocks, sleeps or owns a timer: whatever
// depends on time (reconnect back-off, playback observation, the echo hold, the source watch) runs from `tick()`,
// which the host calls every 20–50 ms, against the host's monotonic clock.
//
// Re-entrancy: neither an `EngineHost` method nor the event callback may call back into the engine; what a host
// method starts (a connection, a capture) reports back later, as its own call on the engine thread. The other way
// round is allowed: an engine method may call any host method before it returns, for example `close` from inside
// `on_transport_text`.
//
// Not in here, because it is platform code: device and process enumeration, level meters (the `meters` event),
// test tones and the diagnostic synthetic microphone.
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <initializer_list>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "livebridge/frame_codec.h"
#include "livebridge/json.h"

namespace livebridge {

/// `out`: the owner's speech, translated for the call. `in`: the call's speech, translated for the owner.
using Direction = AudioFrame::Direction;

/// Why a host call failed: the code and message of the bridge's `error` event. The engine presets it with a general
/// reason before each call; a host that knows better overwrites it, a host that does not just returns false.
struct HostError {
  std::string code;
  std::string message;
};

/// What the engine needs to know about one audio device before it uses it.
struct DeviceInfo {
  int input_channels = 0;
  int output_channels = 0;
  /// A software device (virtual cable, aggregate), not physical hardware.
  bool is_virtual = false;
};

/// Everything the engine asks of the platform. Each method is here because Engine.swift needs it.
class EngineHost {
 public:
  virtual ~EngineHost() = default;

  /// Monotonic microseconds. Stamps capture frames and times the back-off, the echo hold and `e2eMs`.
  virtual std::uint64_t now_us() = 0;

  // ── Gateway connection (GatewayTransport.swift): one at a time ──

  /// Starts connecting: exchange the access token for a session token at `<gateway_url>/v1/sessions`, then open
  /// the WebSocket `<gateway_url>/v1/realtime` with it. Answered by `Engine::on_transport_open` or
  /// `Engine::on_transport_closed`. Noticing a dead peer (pings) is the host's job too.
  virtual void connect(const std::string& gateway_url, const std::string& access_token) = 0;
  /// One JSON control message, already carrying `"v":1`. The engine sends only on an open connection; text and
  /// binary messages leave in the order given.
  virtual void send_text(const std::string& json) = 0;
  /// One encoded audio frame. False when it was dropped because too many frames still wait for the network (the
  /// protocol allows 25 in flight); the engine then warns the user, at most once a second.
  virtual bool send_binary(const std::uint8_t* data, std::size_t size) = 0;
  /// Ends the connection `connect` started, opened or not. Called exactly once per `connect`, also after the host
  /// reported that connection closed. From here on the host delivers nothing more from it — events it had already
  /// queued for the engine thread included.
  virtual void close() = 0;

  // ── Devices ──

  /// Looks up one live audio device; false when there is none with this uid. The engine refuses an unusable route
  /// before it opens anything (incoming speech, for one, is only ever played on a physical device), and stops the
  /// session when a device in use disappears.
  virtual bool find_device(const std::string& uid, DeviceInfo& info) = 0;

  // ── Capture: the audio arrives through `Engine::on_captured` ──

  /// Starts capturing the microphone. False when it cannot be opened.
  virtual bool open_microphone(const std::string& device_uid, HostError& error) = 0;
  virtual void close_microphone() = 0;
  /// Starts capturing what these processes (the meeting app) play, and nothing else on the system.
  virtual bool open_source(const std::vector<int>& process_ids, HostError& error) = 0;
  virtual void close_source() = 0;
  /// True while every captured process still exists. Asked once a second while the source is open.
  virtual bool source_alive() = 0;

  // ── Playback: one sink per direction; `out` plays into the virtual microphone, `in` into the headphones ──

  /// Opens the device and starts it playing silence. A new sink is not muted and its positions start at zero.
  virtual bool open_sink(Direction direction, const std::string& device_uid, HostError& error) = 0;
  virtual void close_sink(Direction direction) = 0;
  /// Queues PCM s16le mono recorded at `sample_rate`: the rate the gateway synthesizes at, or 16 kHz when the
  /// microphone bypasses the server. False when the queue is full and audio was lost (the turn is then cancelled).
  virtual bool sink_write(Direction direction, const std::uint8_t* pcm, std::size_t bytes, int sample_rate) = 0;
  /// End of a turn: what a resampler still holds is queued, and the tail plays without waiting to prebuffer.
  virtual void sink_end_input(Direction direction) = 0;
  /// Drops everything queued; the device plays silence from its next cycle.
  virtual void sink_flush(Direction direction) = 0;
  /// While muted the device keeps draining the queue but plays silence.
  virtual void sink_set_muted(Direction direction, bool muted) = 0;
  /// Samples queued so far, and samples the device has taken so far (flushed ones count as taken); both at the
  /// device's rate, neither ever decreasing. A turn is audible once `consumed` passes the `written` read before its
  /// first frame was queued, and has finished playing when `consumed` reaches the `written` read after its last.
  virtual std::int64_t sink_written(Direction direction) = 0;
  virtual std::int64_t sink_consumed(Direction direction) = 0;
};

/// The `start` map of docs/bridge-contract.md, validated.
struct EngineConfig {
  enum class Mode { captions, incoming, bidirectional };

  std::string gateway_url;
  std::string access_token;
  std::string mic_uid;
  std::string headphones_uid;
  /// Absent: no outgoing audio is possible.
  std::optional<std::string> virtual_mic_uid;
  /// Meeting processes to capture; empty turns the incoming direction off.
  std::vector<int> source_pids;
  /// The owner's language and the remote participant's: codes from packages/protocol/src/languages.ts. The gateway
  /// refuses a code it does not know.
  std::string my_lang;
  std::string target_lang;
  Mode mode = Mode::captions;
  /// "manual" (push-to-talk), "vad" or "turn_prediction".
  std::string out_commit;
  /// Empty: the gateway's default model.
  std::string translation_model;
  /// The synthesized voice chosen for each direction. Empty: the gateway's configured voice. An id that is not
  /// well-formed is treated as not chosen.
  std::string out_voice_id;
  std::string in_voice_id;

  /// False when a required key is missing or has a wrong value; `out` is then left as it was.
  static bool parse(const Json& settings, EngineConfig& out);
};

/// One call's session: both capture lanes, both playback queues and the gateway connection, as a state machine.
/// Destroying an engine does not touch the host: `stop()` first if a session may be running.
class Engine {
 public:
  using EventCallback = std::function<void(const Json&)>;

  /// `host` must outlive the engine. Events are delivered from inside the engine method that caused them.
  Engine(EngineHost& host, EventCallback on_event);
  Engine(const Engine&) = delete;
  Engine& operator=(const Engine&) = delete;

  // ── Commands (the bridge's control methods) ──

  /// False when `settings` is not a valid `start` map; nothing happens then. Otherwise the outcome arrives as
  /// events: a `state` (connecting), or an `error` when the route is unusable or a session is already running.
  bool start(const Json& settings);
  void stop();
  void ptt_down();
  void ptt_up();
  void set_outgoing_muted(bool muted);
  void set_incoming_audio_muted(bool muted);
  /// The physical microphone straight into the virtual microphone, with no server.
  void set_bypass(bool enabled);
  /// Stops everything now: queued audio is discarded, the virtual microphone goes silent, the session is closed.
  void panic();

  // ── From the host ──

  /// The connection `connect` asked for is open.
  void on_transport_open();
  void on_transport_text(std::string_view text);
  void on_transport_binary(const std::uint8_t* data, std::size_t size);
  /// The connection ended without `close` being asked for: it could not be opened, or it dropped. `code` is used
  /// when the session's first connection never opened and becomes that `error` event's code — `gateway_unreachable`,
  /// `unauthorized` (HTTP 401), `session_limit` (429) or `gateway_error`.
  void on_transport_closed(std::string_view code, std::string_view reason);
  /// Captured audio as PCM s16le 16 kHz mono, whole samples, in pieces of any size: `out` from the microphone, `in`
  /// from the meeting source. The engine cuts it into the protocol's 20 ms frames itself.
  void on_captured(Direction direction, const std::uint8_t* pcm, std::size_t bytes);
  /// An audio device was added or removed.
  void on_devices_changed();
  /// Runs whatever has come due. Call it every 20–50 ms; it is cheap, and does nothing while no session runs.
  void tick();

 private:
  enum class Phase { idle, connecting, ready, active, degraded, stopping };

  struct PlayingTurn {
    std::uint32_t id = 0;
    /// Sink sample positions where this turn's audio starts and ends (`end` is set by the turn's last frame).
    std::int64_t start = 0;
    std::int64_t end = 0;
    bool ended = false;
    bool started = false;
  };

  using Members = std::initializer_list<Json::Object::value_type>;

  void start_session(EngineConfig config);
  bool open_audio(const EngineConfig& config, HostError& error);
  void connect();
  void close_transport();
  void connection_lost(const std::string& reason);
  void stop_session(const char* message);
  void release_audio();
  void fence_all();
  void cancel(Direction direction);
  void open_hands_free_capture_if_needed();
  long long display_turn(Direction direction, long long gateway_turn);
  void capture_frame(Direction direction, const std::uint8_t* pcm);
  void received(const Json& message);
  void observe_playback();
  void watch_source();
  void send(const char* type, Members fields);
  void emit(const Json& event);
  void emit_state();
  void emit_error(const std::string& code, const std::string& message, bool fatal, const char* direction = nullptr);

  EngineHost& host_;
  EventCallback on_event_;

  Phase phase_ = Phase::idle;
  std::optional<EngineConfig> config_;
  /// `connect` was asked for and `close` has not been yet / that connection is open.
  bool transport_active_ = false;
  bool transport_open_ = false;
  bool mic_open_ = false;
  bool source_open_ = false;

  // Per direction, indexed out = 0, in = 1.
  bool sink_open_[2] = {false, false};
  bool sink_muted_[2] = {false, false};
  std::uint32_t generation_[2] = {1, 1};
  std::uint32_t capture_sequence_[2] = {0, 0};
  bool direction_ready_[2] = {false, false};
  int synth_rate_[2] = {24'000, 24'000};
  std::vector<PlayingTurn> playing_[2];
  /// Captured audio that does not fill a 20 ms frame yet.
  std::vector<std::uint8_t> pending_capture_[2];
  /// The gateway numbers turns from 1 in every connection. The interface needs ids that stay unique for as long as
  /// the app runs, so each new connection's ids are offset by the highest id already shown.
  long long turn_base_[2] = {0, 0};
  long long highest_turn_[2] = {0, 0};

  bool in_capture_started_ = false;
  bool out_capture_open_ = false;
  bool ptt_held_ = false;
  bool outgoing_muted_ = false;
  bool incoming_audio_muted_ = false;
  bool bypass_ = false;
  bool mock_ = false;
  std::optional<std::string> status_message_;
  int reconnect_attempt_ = 0;
  std::uint64_t reconnect_at_us_ = 0;
  /// When push-to-talk was last released, until the turn it produced becomes audible (end-to-end latency probe).
  std::optional<std::uint64_t> released_at_us_;
  /// Gateway turn id -> measured milliseconds, kept until the gateway's own metrics for that turn arrive.
  std::map<std::uint32_t, long long> end_to_end_ms_;
  std::uint64_t last_backlog_warning_us_ = 0;
  /// Automatic turn modes only: the microphone is not forwarded while translated incoming speech is playing (and
  /// for a moment after), so that speech coming out of loudspeakers is not picked up and translated back.
  std::uint64_t echo_hold_until_us_ = 0;
  std::uint64_t last_source_watch_us_ = 0;
};

}  // namespace livebridge
