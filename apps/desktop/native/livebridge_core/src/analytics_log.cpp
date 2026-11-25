#include "livebridge/analytics_log.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <ctime>
#include <exception>
#include <fstream>
#include <iterator>
#include <limits>
#include <sstream>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

namespace livebridge {
namespace {

namespace fs = std::filesystem;

const std::uintmax_t kMaxBytes = 20 * 1024 * 1024;
const char* const kTimingFields[] = {"e2eMs", "sttCommitMs", "translateFirstMs", "translateTotalMs", "ttsFirstAudioMs"};
const char* const kTurnFields[] = {"e2eMs", "sttCommitMs", "translateFirstMs", "translateTotalMs", "ttsFirstAudioMs",
                                   "ttsTotalMs", "audioMs"};

/// The member `key` when it is a string, else nullptr.
const std::string* string_member(const Json& object, std::string_view key) {
  const Json* value = object.find(key);
  return value && value->is_string() ? &value->as_string() : nullptr;
}

std::string string_or(const Json& object, std::string_view key, const char* fallback) {
  const std::string* value = string_member(object, key);
  return value ? *value : fallback;
}

/// The member `key` when it is a whole number. Like the Swift `as? Int`, a number with a fraction counts as missing.
std::optional<long long> int_member(const Json& object, std::string_view key) {
  const Json* value = object.find(key);
  if (!value || !value->is_number()) return std::nullopt;
  const double number = value->as_number();
  if (number != std::floor(number) || std::fabs(number) >= 9.007199254740992e15) return std::nullopt;
  return static_cast<long long>(number);
}

bool bool_member(const Json& object, std::string_view key) {
  const Json* value = object.find(key);
  return value && value->as_bool();
}

/// The Swift `Int(String)`: an optional sign and digits, nothing else (no spaces, no line break).
std::optional<long long> parse_int(const std::string& text) {
  std::size_t at = !text.empty() && (text[0] == '+' || text[0] == '-') ? 1 : 0;
  if (at == text.size()) return std::nullopt;
  long long value = 0;
  for (; at < text.size(); at++) {
    if (text[at] < '0' || text[at] > '9') return std::nullopt;
    const int digit = text[at] - '0';
    if (value > (std::numeric_limits<long long>::max() - digit) / 10) return std::nullopt;
    value = value * 10 + digit;
  }
  return text[0] == '-' ? -value : value;
}

/// Length of UTF-8 text in Unicode code points: every byte that is not a continuation byte starts one. The Swift
/// log counts user-perceived characters (`String.count`), so a combining sequence or a joined emoji that is one
/// character there is several here. Plain letters of any script count the same in both.
long long code_points(const std::string& text) {
  long long count = 0;
  for (const char c : text)
    if ((static_cast<unsigned char>(c) & 0xC0) != 0x80) count++;
  return count;
}

/// 2026-11-25T09:13:10.120Z: UTC, rounded to the nearest millisecond as the Swift log's ISO8601DateFormatter does.
std::string timestamp(std::chrono::system_clock::time_point now) {
  const auto millis = std::chrono::round<std::chrono::milliseconds>(now);
  const auto seconds = std::chrono::floor<std::chrono::seconds>(millis);
  const std::time_t time = std::chrono::system_clock::to_time_t(seconds);
  std::tm utc{};
#ifdef _WIN32
  gmtime_s(&utc, &time);
#else
  gmtime_r(&time, &utc);
#endif
  char buffer[96];
  std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", utc.tm_year + 1900, utc.tm_mon + 1,
                utc.tm_mday, utc.tm_hour, utc.tm_min, utc.tm_sec, static_cast<int>((millis - seconds).count()));
  return buffer;
}

/// The whole file, or nothing when it cannot be read.
std::string read_text(const fs::path& path) {
  std::ifstream file(path, std::ios::binary);
  std::ostringstream text;
  text << file.rdbuf();
  return text.str();
}

/// Calls `visit` with every line of the log that is a JSON object; anything else (a torn line) is skipped.
template <typename Visit>
void for_each_record(const fs::path& path, Visit visit) {
  std::ifstream file(path, std::ios::binary);
  std::string line;
  Json record;
  while (std::getline(file, line))
    if (!line.empty() && Json::parse(line, record) && record.is_object()) visit(record);
}

/// The path as UTF-8 for the summary (on Windows the native form is UTF-16); empty if it cannot be converted.
std::string utf8_path(const fs::path& path) {
  try {
    const auto text = path.u8string();  // std::string in C++17, std::u8string from C++20
    return std::string(text.begin(), text.end());
  } catch (const std::exception&) {
    return std::string();
  }
}

}  // namespace

AnalyticsLog::AnalyticsLog(fs::path file, Clock clock)
    : path_(std::move(file)),
      counter_path_(fs::path(path_).replace_extension("session")),
      clock_(clock ? std::move(clock) : Clock(std::chrono::system_clock::now)),
      session_started_at_(clock_()) {
  if (const auto saved = parse_int(read_text(counter_path_))) {
    session_ = *saved;
  } else {
    // No counter yet (a log written by an older build): continue after the highest number in it.
    std::optional<long long> highest;
    for_each_record(path_, [&](const Json& entry) {
      const auto number = int_member(entry, "session");
      if (number && (!highest || *number > *highest)) highest = number;
    });
    session_ = highest.value_or(0);
  }
  saved_session_ = session_;
}

bool AnalyticsLog::enabled() const {
  const std::lock_guard<std::mutex> lock(mutex_);
  return enabled_;
}

void AnalyticsLog::set_enabled(bool on) {
  const std::lock_guard<std::mutex> lock(mutex_);
  enabled_ = on;
}

void AnalyticsLog::record(const Json& event) {
  const std::lock_guard<std::mutex> lock(mutex_);
  handle(event);
}

void AnalyticsLog::rate(const std::string& direction, long long turn_id, const std::string& rating) {
  if (rating != "good" && rating != "bad" && rating != "none") return;
  const std::lock_guard<std::mutex> lock(mutex_);
  write({{"type", "rating"}, {"direction", direction}, {"turnId", turn_id}, {"rating", rating}});
}

void AnalyticsLog::clear() {
  const std::lock_guard<std::mutex> lock(mutex_);
  std::error_code ignored;
  fs::remove(path_, ignored);
}

// ── Deriving records from engine events ──

void AnalyticsLog::handle(const Json& event) {
  const std::string* type = string_member(event, "type");
  if (!type) return;
  const std::string direction = string_or(event, "direction", "");
  const long long turn_id = int_member(event, "turnId").value_or(0);
  const std::string key = direction + "#" + std::to_string(turn_id);

  if (*type == "state") {
    const std::string state = string_or(event, "state", "idle");
    if (state == "connecting" && last_state_ == "idle") {
      session_++;
      session_started_at_ = clock_();
      session_turns_ = 0;
    }
    if ((state == "ready" || state == "active") && !session_open_) {
      session_open_ = true;
      session_is_mock_ = bool_member(event, "mock");
      Json::Object fields{{"type", "session_start"}};
      for (const char* field : {"mode", "myLang", "targetLang", "outCommit"})
        if (const std::string* value = string_member(event, field)) fields.emplace_back(field, *value);
      write(std::move(fields));
    }
    if (state == "degraded" && last_state_ != "degraded") write({{"type", "reconnect"}});
    if (state == "idle" && session_open_) {
      // Whole seconds, the fraction cut off.
      const auto duration = std::chrono::duration_cast<std::chrono::seconds>(clock_() - session_started_at_);
      const long long seconds = duration.count();
      write({{"type", "session_end"}, {"turns", session_turns_}, {"durationSec", seconds}});
      session_open_ = false;
      pending_.clear();
      awaiting_e2e_.clear();
    }
    last_state_ = state;
  } else if (*type == "caption") {
    // Only the length of the text is kept, never the text.
    const std::string* text = string_member(event, "text");
    const long long length = text ? code_points(*text) : 0;
    const std::string kind = string_or(event, "kind", "");
    if (kind == "final") {
      pending_[key].source_chars = length;
    } else if (kind == "translationFinal") {
      pending_[key].translation_chars = length;
    } else if (kind == "partial" && length == 0) {
      write({{"type", "empty_turn"}, {"direction", direction}});
    }
  } else if (*type == "metrics") {
    if (event.find("translateTotalMs")) {
      // The gateway's stage timings arrive once per translated turn.
      Json::Object fields{{"type", "turn"}, {"direction", direction}, {"turnId", turn_id}};
      for (const char* field : kTurnFields)
        if (const auto value = int_member(event, field)) fields.emplace_back(field, *value);
      if (const std::string* model = string_member(event, "model")) fields.emplace_back("model", *model);
      PendingTurn turn;
      if (const auto found = pending_.find(key); found != pending_.end()) {
        turn = found->second;
        pending_.erase(found);
      }
      if (turn.source_chars) fields.emplace_back("sourceChars", *turn.source_chars);
      if (turn.translation_chars) fields.emplace_back("translationChars", *turn.translation_chars);
      const bool timed = int_member(event, "e2eMs").has_value();
      if (!timed && turn.e2e_ms) fields.emplace_back("e2eMs", *turn.e2e_ms);
      if (!timed && !turn.e2e_ms) awaiting_e2e_.insert(key);
      session_turns_++;
      write(std::move(fields));
    } else if (const auto e2e = int_member(event, "e2eMs")) {
      // The client's own observation: push-to-talk release -> first audible translated sample.
      if (awaiting_e2e_.erase(key) > 0) {
        write({{"type", "e2e"}, {"direction", direction}, {"turnId", turn_id}, {"e2eMs", *e2e}});
      } else {
        pending_[key].e2e_ms = *e2e;
      }
    }
  } else if (*type == "error") {
    Json::Object fields{{"type", "error"}, {"code", string_or(event, "code", "error")}};
    fields.emplace_back("fatal", bool_member(event, "fatal"));
    if (!direction.empty()) fields.emplace_back("direction", direction);
    write(std::move(fields));
  }
}

void AnalyticsLog::write(Json::Object fields) {
  if (!enabled_) return;
  fields.emplace_back("t", timestamp(clock_()));
  fields.emplace_back("session", session_);
  fields.emplace_back("mock", session_is_mock_);
  // Byte order, which for these ASCII keys is the order the Swift log writes them in (`.sortedKeys`).
  std::sort(fields.begin(), fields.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
  const std::string line = Json(std::move(fields)).dump() + "\n";

  std::error_code failed;
  if (path_.has_parent_path()) fs::create_directories(path_.parent_path(), failed);
  if (session_ > saved_session_) {
    save_counter();
    saved_session_ = session_;
  }
  const std::uintmax_t size = fs::file_size(path_, failed);
  if (!failed && size > kMaxBytes) {
    // Bounded on disk: keep one previous file, start a new one.
    const fs::path old = fs::path(path_).replace_extension("old.jsonl");
    fs::remove(old, failed);
    fs::rename(path_, old, failed);
  }
  // Binary, so a line ends with "\n" on Windows too.
  std::ofstream file(path_, std::ios::binary | std::ios::app);
  file.write(line.data(), static_cast<std::streamsize>(line.size()));
}

void AnalyticsLog::save_counter() const {
  // Written beside the counter and renamed over it, so a crash never leaves half a number.
  fs::path temporary = counter_path_;
  temporary += ".tmp";
  {
    std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
    file << std::to_string(session_);
  }
  std::error_code failed;
  fs::rename(temporary, counter_path_, failed);
  if (failed) fs::remove(temporary, failed);
}

// ── Summary ──

Json AnalyticsLog::summary() const {
  const std::lock_guard<std::mutex> lock(mutex_);
  long long sessions = 0, turns = 0, reconnects = 0, empty_turns = 0;
  std::vector<long long> samples[std::size(kTimingFields)];
  std::map<std::string, long long> errors;
  std::map<std::string, std::string> ratings;
  std::optional<std::string> first_at, last_at;
  bool first = true;

  for_each_record(path_, [&](const Json& entry) {
    // The first and the last entry give the period, whatever they are.
    const std::string* at = string_member(entry, "t");
    last_at = at ? std::optional<std::string>(*at) : std::nullopt;
    if (first) first_at = last_at;
    first = false;

    if (bool_member(entry, "mock")) return;
    const std::string type = string_or(entry, "type", "");
    if (type == "session_start") {
      sessions++;
    } else if (type == "reconnect") {
      reconnects++;
    } else if (type == "empty_turn") {
      empty_turns++;
    } else if (type == "error") {
      errors[string_or(entry, "code", "error")]++;
    } else if (type == "turn" || type == "e2e") {
      if (type == "turn") turns++;
      for (std::size_t i = 0; i < std::size(kTimingFields); i++)
        if (const auto value = int_member(entry, kTimingFields[i])) samples[i].push_back(*value);
    } else if (type == "rating") {
      // The latest judgement of a turn wins; "none" withdraws it.
      const auto part = [&](const char* name, const Json& missing) {
        const Json* value = entry.find(name);
        return (value ? *value : missing).dump();
      };
      const std::string turn =
          part("session", Json(0)) + "#" + part("direction", Json("")) + "#" + part("turnId", Json(0));
      if (const std::string* rating = string_member(entry, "rating")) {
        ratings[turn] = *rating;
      } else {
        ratings.erase(turn);
      }
    }
  });

  long long rated_good = 0, rated_bad = 0;
  for (const auto& rating : ratings) {
    if (rating.second == "good") rated_good++;
    if (rating.second == "bad") rated_bad++;
  }
  std::error_code failed;
  const std::uintmax_t size = fs::file_size(path_, failed);

  Json::Object result{{"enabled", enabled_},
                      {"path", utf8_path(path_)},
                      {"fileSizeBytes", failed ? 0ULL : static_cast<unsigned long long>(size)},
                      {"sessions", sessions},
                      {"turns", turns}};
  if (first_at) result.emplace_back("firstAt", *first_at);
  if (last_at) result.emplace_back("lastAt", *last_at);
  for (std::size_t i = 0; i < std::size(kTimingFields); i++) {
    std::vector<long long>& sorted = samples[i];
    if (sorted.empty()) continue;
    std::sort(sorted.begin(), sorted.end());
    const long long count = static_cast<long long>(sorted.size());
    const auto percentile = [&](double p) {
      const long long rank = static_cast<long long>(std::ceil(p * static_cast<double>(count)));
      return sorted[static_cast<std::size_t>(std::min(count - 1, std::max(0LL, rank - 1)))];
    };
    result.emplace_back(kTimingFields[i], Json::Object{{"count", count},
                                                       {"p50", percentile(0.5)},
                                                       {"p95", percentile(0.95)},
                                                       {"max", sorted.back()}});
  }
  Json::Object error_counts;
  for (const auto& error : errors) error_counts.emplace_back(error.first, error.second);
  result.emplace_back("errors", std::move(error_counts));
  result.emplace_back("reconnects", reconnects);
  result.emplace_back("emptyTurns", empty_turns);
  result.emplace_back("ratedGood", rated_good);
  result.emplace_back("ratedBad", rated_bad);
  return Json(std::move(result));
}

}  // namespace livebridge
