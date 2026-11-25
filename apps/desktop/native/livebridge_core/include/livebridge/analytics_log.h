// Local usage log for judging speed and quality over time (the C++ twin of the Swift AnalyticsLog).
//
// It records numbers only: timings, counts, error codes, text lengths and the owner's thumbs-up / thumbs-down.
// Transcript and translation text never reach the file. One JSON object per line, keys in alphabetical order
// (`type`: session_start, turn, e2e, empty_turn, error, reconnect, rating, session_end), each with `t` (ISO-8601
// UTC with milliseconds), `session` and `mock`. An opted-in install uploads these records, so their field names
// and types are a contract: docs/telemetry-api.md.
//
// Feed it the same event maps the engine emits (docs/bridge-contract.md); it derives the records itself.
//
// Every method is synchronous and guarded by one mutex, so the engine thread and the UI thread can share a log.
// A record is on disk when `record` returns (the Swift log queues it instead): never call it from an audio callback.
#pragma once

#include <chrono>
#include <filesystem>
#include <functional>
#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <string>

#include "livebridge/json.h"

namespace livebridge {

class AnalyticsLog {
 public:
  using Clock = std::function<std::chrono::system_clock::time_point()>;

  /// Reads the per-install session counter kept next to the log (`<name>.session`); without one, numbering
  /// continues after the highest session in an existing log. `clock` is replaced in tests only.
  explicit AnalyticsLog(std::filesystem::path file, Clock clock = std::chrono::system_clock::now);

  AnalyticsLog(const AnalyticsLog&) = delete;
  AnalyticsLog& operator=(const AnalyticsLog&) = delete;

  const std::filesystem::path& path() const { return path_; }

  bool enabled() const;
  /// A disabled log still follows the session (its number, its turns) but writes nothing.
  void set_enabled(bool on);

  /// Takes one engine event: `state`, `caption`, `metrics` or `error`; anything else is ignored.
  void record(const Json& event);

  /// The owner's judgement of a translation: `good`, `bad` or `none` (withdrawn). Any other rating is ignored.
  void rate(const std::string& direction, long long turn_id, const std::string& rating);

  /// Deletes the log file. The session counter stays, so a session number is never reused by this install.
  void clear();

  /// Aggregates the log for the analytics panel (shape: docs/bridge-contract.md). Sessions against fake providers
  /// are left out of every figure.
  Json summary() const;

 private:
  struct PendingTurn {
    std::optional<long long> source_chars;
    std::optional<long long> translation_chars;
    std::optional<long long> e2e_ms;
  };

  void handle(const Json& event);
  void write(Json::Object fields);
  void save_counter() const;

  const std::filesystem::path path_;
  /// Survives `clear()`: the collector merges a turn's records by (install, session, direction, turn).
  const std::filesystem::path counter_path_;
  const Clock clock_;

  mutable std::mutex mutex_;
  bool enabled_ = true;
  /// Numbered per install, across app launches and "Clear log".
  long long session_ = 0;
  long long saved_session_ = 0;
  bool session_open_ = false;
  bool session_is_mock_ = false;
  std::chrono::system_clock::time_point session_started_at_;
  long long session_turns_ = 0;
  std::string last_state_ = "idle";
  std::map<std::string, PendingTurn> pending_;
  /// Turns already written whose end-to-end time had not been observed yet.
  std::set<std::string> awaiting_e2e_;
};

}  // namespace livebridge
