// Tests of the numbers-only analytics log: the Swift AnalyticsLogTests, plus what the C++ twin has to prove on its
// own (record shapes, timestamps, key order, code-point lengths, rotation, two threads).
// Usage: analytics_tests [fixture path, not used]
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <random>
#include <sstream>
#include <string>
#include <system_error>
#include <thread>
#include <vector>

#include "check.h"
#include "livebridge/analytics_log.h"
#include "livebridge/json.h"

using namespace livebridge;
namespace fs = std::filesystem;

/// A fresh directory per test, removed afterwards. The log creates it with its first line.
struct Scratch {
  fs::path dir;
  fs::path file;

  Scratch() {
    static int serial = 0;
    const std::string name = "lb-analytics-" + std::to_string(std::random_device{}()) + "-" + std::to_string(serial++);
    dir = fs::temp_directory_path() / name;
    file = dir / "analytics.jsonl";
  }
  ~Scratch() {
    std::error_code ignored;
    fs::remove_all(dir, ignored);
  }
};

static std::string read(const fs::path& path) {
  std::ifstream file(path, std::ios::binary);
  std::stringstream text;
  text << file.rdbuf();
  return text.str();
}

static std::vector<std::string> lines(const fs::path& path) {
  std::ifstream file(path, std::ios::binary);
  std::vector<std::string> all;
  for (std::string line; std::getline(file, line);) all.push_back(line);
  return all;
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

static bool contains(const std::string& text, const std::string& part) { return text.find(part) != std::string::npos; }

/// A whole-number member, or -1 when it is missing.
static long long number(const Json& object, const char* key) {
  const Json* value = object.find(key);
  return value && value->is_number() ? value->as_int() : -1;
}

static std::string dumped(const Json& object, const char* key) {
  const Json* value = object.find(key);
  return value ? value->dump() : "missing";
}

static std::string utf8(const fs::path& path) {
  const auto text = path.u8string();
  return std::string(text.begin(), text.end());
}

static Json state(const char* name, bool mock = false) {
  return Json::Object{{"type", "state"}, {"state", name}, {"mock", mock}};
}

static Json caption(const char* direction, int id, const char* kind, const std::string& text) {
  return Json::Object{{"type", "caption"}, {"direction", direction}, {"turnId", id}, {"kind", kind}, {"text", text}};
}

/// One push-to-talk turn the way the engine reports it: captions, the client's end-to-end time, then the
/// gateway's stage timings.
static void turn(AnalyticsLog& log, int id, int e2e, const std::string& source, const std::string& translation,
                 bool e2e_first = true) {
  log.record(caption("out", id, "final", source));
  log.record(caption("out", id, "translationFinal", translation));
  const Json local = Json::Object{{"type", "metrics"}, {"direction", "out"}, {"turnId", id}, {"e2eMs", e2e}};
  Json server = Json::Object{{"type", "metrics"}, {"direction", "out"}, {"turnId", id}, {"sttCommitMs", 300},
                             {"translateFirstMs", 600}, {"translateTotalMs", 700}, {"ttsFirstAudioMs", 250},
                             {"audioMs", 2400}, {"model", "gemini-3.5-flash-lite"}};
  if (e2e_first) {
    log.record(local);
    server.set("e2eMs", e2e);
    log.record(server);
  } else {
    log.record(server);
    log.record(local);
  }
}

/// 2026-11-25T09:13:10.120Z and 300 microseconds more, which a timestamp rounds away.
static std::chrono::system_clock::time_point morning() {
  return std::chrono::system_clock::from_time_t(1795597990) + std::chrono::microseconds(120'300);
}

// ── The Swift AnalyticsLogTests ──

static void test_records_numbers_only_and_summarises_them() {
  Scratch scratch;
  AnalyticsLog log(scratch.file);
  const std::string secret = "Maoshim oyiga uch ming dollar";
  log.record(state("connecting"));
  log.record(state("ready"));
  const int e2e[] = {1200, 1400, 1300, 2600};
  for (int index = 0; index < 4; index++)
    turn(log, index + 1, e2e[index], secret, "My salary is three thousand dollars a month", index != 3);
  log.record(caption("out", 5, "partial", ""));
  log.record(Json::Object{{"type", "error"}, {"code", "translation_failed"}, {"direction", "out"}, {"fatal", false}});
  log.record(state("degraded"));
  log.record(state("ready"));
  log.rate("out", 1, "good");
  log.rate("out", 2, "bad");
  log.rate("out", 2, "good");
  log.rate("out", 3, "bad");
  log.rate("out", 3, "none");
  log.record(state("idle"));

  const Json summary = log.summary();
  const std::string written = read(scratch.file);
  // Privacy: lengths are recorded, text never is.
  CHECK(!contains(written, "Maoshim"));
  CHECK(!contains(written, "salary"));
  CHECK(contains(written, "\"sourceChars\":" + std::to_string(secret.size())));
  CHECK(contains(written, "\"translationChars\":43"));
  CHECK(contains(written, "\"model\":\"gemini-3.5-flash-lite\""));

  CHECK(number(summary, "sessions") == 1);
  CHECK(number(summary, "turns") == 4);
  CHECK(number(summary, "emptyTurns") == 1);
  CHECK(number(summary, "reconnects") == 1);
  CHECK(dumped(summary, "errors") == R"({"translation_failed":1})");
  // Turn 2's last rating is "good"; turn 3's was withdrawn.
  CHECK(number(summary, "ratedGood") == 2);
  CHECK(number(summary, "ratedBad") == 0);
  // All four end-to-end times count, including the one observed after the gateway's timings arrived.
  CHECK(dumped(summary, "e2eMs") == R"({"count":4,"p50":1300,"p95":2600,"max":2600})");
  CHECK(dumped(summary, "translateFirstMs") == R"({"count":4,"p50":600,"p95":600,"max":600})");
  CHECK(summary.find("path") && summary.find("path")->as_string() == utf8(scratch.file));
  CHECK(summary.find("firstAt") && summary.find("firstAt")->is_string());
  CHECK(summary.find("lastAt") && summary.find("lastAt")->is_string());
  CHECK(summary.find("enabled") && summary.find("enabled")->as_bool());
  CHECK(number(summary, "fileSizeBytes") == static_cast<long long>(written.size()));
  CHECK(written.size() > 100);
}

static void test_mock_sessions_are_kept_out_of_the_figures() {
  Scratch scratch;
  AnalyticsLog log(scratch.file);
  log.record(state("connecting"));
  log.record(state("ready", true));
  turn(log, 1, 190, "x", "y");
  log.record(state("idle"));
  const Json summary = log.summary();
  CHECK(number(summary, "sessions") == 0);
  CHECK(number(summary, "turns") == 0);
  CHECK(summary.find("e2eMs") == nullptr);
  // The records are in the file, marked, so the uploader can leave them out too.
  const auto written = lines(scratch.file);
  CHECK(written.size() == 3);
  for (const std::string& line : written) CHECK(contains(line, "\"mock\":true"));
}

static void test_disabled_log_writes_nothing_and_clear_removes_the_file() {
  Scratch scratch;
  AnalyticsLog log(scratch.file);
  CHECK(log.enabled());
  log.set_enabled(false);
  log.record(state("connecting"));
  log.record(state("ready"));
  turn(log, 1, 1000, "x", "y");
  CHECK(number(log.summary(), "turns") == 0);
  CHECK(!fs::exists(scratch.file));
  CHECK(!fs::exists(scratch.dir));
  CHECK(log.summary().find("enabled") && !log.summary().find("enabled")->as_bool());
  CHECK(!log.enabled());

  log.set_enabled(true);
  log.record(state("idle"));
  log.record(state("connecting"));
  log.record(state("active"));
  turn(log, 1, 1000, "x", "y");
  CHECK(number(log.summary(), "turns") == 1);
  log.clear();
  CHECK(!fs::exists(scratch.file));
  CHECK(number(log.summary(), "turns") == 0);
  CHECK(number(log.summary(), "fileSizeBytes") == 0);
}

/// Runs one session and returns the session number of the last line written.
static long long run_session(AnalyticsLog& log) {
  log.record(state("connecting"));
  log.record(state("ready"));
  log.record(state("idle"));
  const auto written = lines(log.path());
  CHECK(!written.empty());
  return written.empty() ? -1 : number(parse(written.back()), "session");
}

/// The collector merges a turn's records by (install, session, direction, turn), so a session number must never
/// repeat for one install: not after an app restart and not after "Clear log".
static void test_session_numbers_continue_across_launches_and_clear() {
  Scratch scratch;
  const fs::path counter = scratch.dir / "analytics.session";
  {
    AnalyticsLog first(scratch.file);
    CHECK(run_session(first) == 1);
    CHECK(run_session(first) == 2);
    CHECK(read(counter) == "2");
  }
  {
    // A new launch.
    AnalyticsLog second(scratch.file);
    CHECK(run_session(second) == 3);
  }
  {
    // "Clear log", then another launch.
    AnalyticsLog cleared(scratch.file);
    cleared.clear();
    CHECK(!fs::exists(scratch.file));
    CHECK(read(counter) == "3");
    AnalyticsLog next(scratch.file);
    CHECK(run_session(next) == 4);
  }
  {
    // A log from a build without the counter file: numbering continues after the highest number in it.
    fs::remove(counter);
    AnalyticsLog seeded(scratch.file);
    CHECK(run_session(seeded) == 5);
    CHECK(read(counter) == "5");
    CHECK(!fs::exists(scratch.dir / "analytics.session.tmp"));
  }
  {
    // A counter that is not a plain number is not trusted: the log decides again.
    std::ofstream(counter, std::ios::binary | std::ios::trunc) << "5 or so";
    AnalyticsLog repaired(scratch.file);
    CHECK(run_session(repaired) == 6);
    CHECK(read(counter) == "6");
  }
}

// ── What is uploaded later: docs/telemetry-api.md ──

static void test_record_shapes_match_the_telemetry_contract() {
  Scratch scratch;
  auto now = morning();
  AnalyticsLog log(scratch.file, [&now] { return now; });
  const std::string at = R"("session":1,"t":"2026-11-25T09:13:10.120Z")";

  log.record(state("connecting"));
  // The engine's state event carries more than the log keeps.
  log.record(Json::Object{{"type", "state"}, {"state", "ready"}, {"outReady", true}, {"inReady", true},
                          {"capturing", false}, {"mock", false}, {"bypass", false}, {"message", "Tayyor"},
                          {"mode", "bidirectional"}, {"myLang", "uz"}, {"targetLang", "en"}, {"outCommit", "manual"}});
  // A turn with every timing (the example of the contract).
  log.record(caption("out", 1, "partial", "Mao"));
  log.record(caption("out", 1, "final", "Maoshim oyiga uch ming dollar bo'ladi"));
  log.record(caption("out", 1, "translationDelta", "My"));
  log.record(caption("out", 1, "translationFinal", "My salary is three thousand a month"));
  log.record(Json::Object{{"type", "metrics"}, {"direction", "out"}, {"turnId", 1}, {"e2eMs", 1350}});
  log.record(Json::Object{{"type", "metrics"}, {"direction", "out"}, {"turnId", 1}, {"sttCommitMs", 302},
                          {"translateFirstMs", 690}, {"translateTotalMs", 760}, {"ttsFirstAudioMs", 238},
                          {"ttsTotalMs", 900}, {"audioMs", 2480}, {"model", "gemini-3.5-flash-lite"}, {"e2eMs", 1350}});
  // The other side's turn: the gateway's timings first, the end-to-end time afterwards.
  log.record(Json::Object{{"type", "metrics"}, {"direction", "in"}, {"turnId", 2}, {"translateTotalMs", 410}});
  log.record(Json::Object{{"type", "metrics"}, {"direction", "in"}, {"turnId", 2}, {"e2eMs", 1500}});
  log.record(caption("out", 3, "partial", ""));
  log.record(Json::Object{{"type", "error"}, {"code", "translation_failed"}, {"message", "Tarjima bo'lmadi"},
                          {"direction", "out"}, {"fatal", false}});
  log.record(Json::Object{{"type", "error"}, {"message", "Uzildi"}, {"fatal", true}});
  log.record(state("degraded"));
  log.record(state("degraded"));
  log.rate("out", 1, "good");
  now += std::chrono::milliseconds(193'900);
  log.record(state("idle"));

  const std::vector<std::string> expected = {
      R"({"mock":false,"mode":"bidirectional","myLang":"uz","outCommit":"manual",)" + at +
          R"(,"targetLang":"en","type":"session_start"})",
      R"({"audioMs":2480,"direction":"out","e2eMs":1350,"mock":false,"model":"gemini-3.5-flash-lite",)"
      R"("session":1,"sourceChars":37,"sttCommitMs":302,"t":"2026-11-25T09:13:10.120Z","translateFirstMs":690,)"
      R"("translateTotalMs":760,"translationChars":35,"ttsFirstAudioMs":238,"ttsTotalMs":900,"turnId":1,)"
      R"("type":"turn"})",
      R"({"direction":"in","mock":false,)" + at + R"(,"translateTotalMs":410,"turnId":2,"type":"turn"})",
      R"({"direction":"in","e2eMs":1500,"mock":false,)" + at + R"(,"turnId":2,"type":"e2e"})",
      R"({"direction":"out","mock":false,)" + at + R"(,"type":"empty_turn"})",
      R"({"code":"translation_failed","direction":"out","fatal":false,"mock":false,)" + at + R"(,"type":"error"})",
      R"({"code":"error","fatal":true,"mock":false,)" + at + R"(,"type":"error"})",
      R"({"mock":false,)" + at + R"(,"type":"reconnect"})",
      R"({"direction":"out","mock":false,"rating":"good",)" + at + R"(,"turnId":1,"type":"rating"})",
      // 193.9 s later: whole seconds, cut off.
      R"({"durationSec":193,"mock":false,"session":1,"t":"2026-11-25T09:16:24.020Z","turns":2,"type":"session_end"})",
  };
  const auto written = lines(scratch.file);
  CHECK(written.size() == expected.size());
  for (std::size_t i = 0; i < written.size() && i < expected.size(); i++) {
    CHECK(written[i] == expected[i]);
    if (written[i] != expected[i]) std::printf("  line %zu: %s\n", i + 1, written[i].c_str());
  }
  // One "\n" after every line, nothing else between them.
  const std::string text = read(scratch.file);
  CHECK(!text.empty() && text.back() == '\n' && !contains(text, "\r") && !contains(text, "\n\n"));
  // No words from the captions or the messages.
  for (const char* word : {"Mao", "salary", "Tayyor", "Tarjima", "Uzildi"}) CHECK(!contains(text, word));

  const Json summary = log.summary();
  CHECK(dumped(summary, "firstAt") == R"("2026-11-25T09:13:10.120Z")");
  CHECK(dumped(summary, "lastAt") == R"("2026-11-25T09:16:24.020Z")");
  CHECK(dumped(summary, "e2eMs") == R"({"count":2,"p50":1350,"p95":1500,"max":1500})");
  CHECK(dumped(summary, "errors") == R"({"error":1,"translation_failed":1})");
}

/// 2026-11-25T09:13:10.120Z
static bool looks_like_a_timestamp(const std::string& text) {
  const std::string shape = "dddd-dd-ddTdd:dd:dd.dddZ";
  if (text.size() != shape.size()) return false;
  for (std::size_t i = 0; i < shape.size(); i++) {
    const bool digit = text[i] >= '0' && text[i] <= '9';
    if (shape[i] == 'd' ? !digit : text[i] != shape[i]) return false;
  }
  return true;
}

static void test_timestamps_are_utc_with_milliseconds() {
  // The real clock: the shape, and a time between "before" and "after" (ISO-8601 in UTC sorts as text).
  Scratch real;
  AnalyticsLog log(real.file);
  log.rate("out", 1, "good");
  const auto written = lines(real.file);
  CHECK(written.size() == 1);
  if (written.size() != 1) return;
  const Json rating = parse(written[0]);
  const std::string stamp = rating.find("t") ? rating.find("t")->as_string() : "";
  CHECK(looks_like_a_timestamp(stamp));
  CHECK(stamp > "2026-01-01T00:00:00.000Z" && stamp < "2100-01-01T00:00:00.000Z");

  // An injected clock: exact text, at the epoch and around a leap day, rounded to the nearest millisecond
  // (the Swift log's formatter rounds too: …59.9996 s is written as the next second).
  Scratch fixed;
  auto now = std::chrono::system_clock::from_time_t(0);
  AnalyticsLog timed(fixed.file, [&now] { return now; });
  timed.rate("out", 1, "good");
  now = std::chrono::system_clock::from_time_t(1709251199) + std::chrono::microseconds(998'600);
  timed.rate("out", 1, "good");
  now = std::chrono::system_clock::from_time_t(1709251199) + std::chrono::microseconds(999'600);
  timed.rate("out", 1, "good");
  now = std::chrono::system_clock::from_time_t(1709251200) + std::chrono::microseconds(7'400);
  timed.rate("out", 1, "good");
  const auto stamped = lines(fixed.file);
  CHECK(stamped.size() == 4);
  if (stamped.size() != 4) return;
  CHECK(dumped(parse(stamped[0]), "t") == R"("1970-01-01T00:00:00.000Z")");
  CHECK(dumped(parse(stamped[1]), "t") == R"("2024-02-29T23:59:59.999Z")");
  CHECK(dumped(parse(stamped[2]), "t") == R"("2024-03-01T00:00:00.000Z")");
  CHECK(dumped(parse(stamped[3]), "t") == R"("2024-03-01T00:00:00.007Z")");
}

static void test_keys_of_a_written_line_are_sorted() {
  Scratch scratch;
  AnalyticsLog log(scratch.file);
  log.record(state("connecting"));
  log.record(Json::Object{{"type", "state"}, {"state", "active"}, {"targetLang", "en"}, {"outCommit", "vad"},
                          {"myLang", "uz"}, {"mode", "incoming"}});
  turn(log, 1, 1200, "bir", "one");
  turn(log, 2, 1300, "ikki", "two", false);
  log.record(caption("in", 3, "partial", ""));
  log.record(Json::Object{{"fatal", true}, {"direction", "in"}, {"code", "stt_failed"}, {"type", "error"}});
  log.record(state("degraded"));
  log.rate("in", 2, "bad");
  log.record(state("idle"));

  const auto written = lines(scratch.file);
  CHECK(written.size() == 9);
  for (const std::string& line : written) {
    const Json record = parse(line);
    const Json::Object& members = record.as_object();
    CHECK(members.size() >= 4);
    for (std::size_t i = 1; i < members.size(); i++) CHECK(members[i - 1].first < members[i].first);
    // Written compactly: what is parsed and written again is the same line.
    CHECK(record.dump() == line);
  }
}

static void test_caption_length_is_counted_in_code_points() {
  Scratch scratch;
  AnalyticsLog log(scratch.file);
  log.record(state("connecting"));
  log.record(state("ready"));
  // Ten Cyrillic characters in 19 bytes; "ok " and one emoji (U+1F600, 4 bytes).
  turn(log, 1, 900, "Салом дунё", "ok \xF0\x9F\x98\x80");
  // Code points, not user-perceived characters: "e" with a combining accent is 2 (the Swift log says 1).
  turn(log, 2, 900, "e\xCC\x81", "");
  const auto written = lines(scratch.file);
  CHECK(written.size() == 3);
  if (written.size() != 3) return;
  CHECK(number(parse(written[1]), "sourceChars") == 10);
  CHECK(number(parse(written[1]), "translationChars") == 4);
  CHECK(number(parse(written[2]), "sourceChars") == 2);
  CHECK(number(parse(written[2]), "translationChars") == 0);
  CHECK(!contains(read(scratch.file), "Салом"));
}

// ── The rest of the behaviour ──

static void test_summary_of_an_existing_log() {
  Scratch scratch;
  fs::create_directories(scratch.dir);
  {
    std::ofstream file(scratch.file, std::ios::binary);
    // A mock session first and last: it gives the period but none of the figures.
    file << R"({"mock":true,"session":1,"t":"2026-11-01T08:00:00.000Z","type":"session_start"})" << "\n";
    file << R"({"e2eMs":90,"mock":true,"session":1,"t":"2026-11-01T08:00:01.000Z","turnId":1,"type":"turn"})" << "\n";
    file << R"({"mock":false,"session":2,"t":"2026-11-02T08:00:00.000Z","type":"session_start"})" << "\n";
    for (int i = 20; i >= 1; i--) {
      file << R"({"direction":"out","mock":false,"session":2,"t":"2026-11-02T08:00:01.000Z","turnId":)" << i
           << R"(,"type":"turn","e2eMs":)" << i * 100 << "}\n";
    }
    // Not records: a torn line, a list, a number with a fraction where a whole one is expected.
    file << R"({"direction":"out","mock":false,"session":2,"t":"2026-11-02T08:0)" << "\n";
    file << "[1,2,3]\n\n";
    file << R"({"mock":false,"session":2,"sttCommitMs":301.5,"t":"2026-11-02T08:00:02.000Z","type":"e2e"})" << "\n";
    // The same turn number in another session and in the other direction is another turn.
    file << R"({"direction":"out","mock":false,"rating":"bad","session":2,"turnId":1,"type":"rating"})" << "\n";
    file << R"({"direction":"in","mock":false,"rating":"bad","session":2,"turnId":1,"type":"rating"})" << "\n";
    file << R"({"direction":"out","mock":false,"rating":"good","session":3,"turnId":1,"type":"rating"})" << "\n";
    file << R"({"direction":"out","mock":true,"rating":"good","session":1,"turnId":1,"type":"rating"})" << "\n";
    file << R"({"fatal":true,"mock":false,"session":2,"t":"x","type":"error"})" << "\n";
    file << R"({"mock":true,"session":9,"t":"2026-11-03T08:00:00.000Z","type":"session_end"})";  // no line break
  }
  AnalyticsLog log(scratch.file);
  const Json summary = log.summary();
  CHECK(number(summary, "sessions") == 1);
  CHECK(number(summary, "turns") == 20);
  // 20 samples 100…2000: the median is the 10th, the 95th percentile the 19th.
  CHECK(dumped(summary, "e2eMs") == R"({"count":20,"p50":1000,"p95":1900,"max":2000})");
  CHECK(summary.find("sttCommitMs") == nullptr);
  CHECK(number(summary, "ratedGood") == 1);
  CHECK(number(summary, "ratedBad") == 2);
  CHECK(dumped(summary, "errors") == R"({"error":1})");
  CHECK(dumped(summary, "firstAt") == R"("2026-11-01T08:00:00.000Z")");
  CHECK(dumped(summary, "lastAt") == R"("2026-11-03T08:00:00.000Z")");
  CHECK(number(summary, "fileSizeBytes") == static_cast<long long>(fs::file_size(scratch.file)));
}

static void test_ignores_what_it_cannot_use() {
  Scratch scratch;
  AnalyticsLog log(scratch.file);
  log.record(Json("not a map"));
  log.record(Json::Object{{"state", "ready"}});
  log.record(Json::Object{{"type", "meters"}, {"mic", -32.5}});
  log.record(Json::Object{{"type", "devicesChanged"}});
  log.record(caption("out", 1, "skipped", ""));
  log.rate("out", 1, "great");
  CHECK(!fs::exists(scratch.file));

  // A timing that is not a whole number is left out; the turn is still a turn.
  log.record(state("connecting"));
  log.record(state("ready"));
  log.record(Json::Object{{"type", "metrics"}, {"direction", "out"}, {"turnId", 1}, {"translateTotalMs", 700.5},
                          {"sttCommitMs", 300}, {"model", 7}});
  const auto written = lines(scratch.file);
  CHECK(written.size() == 2);
  if (written.size() != 2) return;
  CHECK(dumped(parse(written[1]), "sttCommitMs") == "300");
  CHECK(parse(written[1]).find("translateTotalMs") == nullptr);
  CHECK(parse(written[1]).find("model") == nullptr);
  CHECK(number(log.summary(), "turns") == 1);
}

static void test_a_full_log_is_set_aside() {
  const std::uintmax_t limit = 20 * 1024 * 1024;
  const char* line = R"({"mock":false,"session":7,"t":"2026-11-01T08:00:00.000Z","type":"reconnect"})";
  {
    // Over the limit: the file becomes analytics.old.jsonl (replacing an earlier one) and a new log starts.
    Scratch scratch;
    const fs::path old = scratch.dir / "analytics.old.jsonl";
    fs::create_directories(scratch.dir);
    std::ofstream(scratch.file, std::ios::binary) << line << "\n";
    std::ofstream(old, std::ios::binary) << "an earlier log\n";
    fs::resize_file(scratch.file, limit + 1);  // filled up with zero bytes
    AnalyticsLog log(scratch.file);
    CHECK(run_session(log) == 8);
    CHECK(fs::exists(old) && fs::file_size(old) == limit + 1);
    CHECK(lines(scratch.file).size() == 2);
    CHECK(run_session(log) == 9);
    CHECK(lines(scratch.file).size() == 4);
    CHECK(fs::file_size(old) == limit + 1);
  }
  {
    // Exactly at the limit: one more line still goes to the same file.
    Scratch scratch;
    fs::create_directories(scratch.dir);
    std::ofstream(scratch.file, std::ios::binary) << line << "\n";
    fs::resize_file(scratch.file, limit);
    AnalyticsLog log(scratch.file);
    log.rate("out", 1, "good");
    CHECK(!fs::exists(scratch.dir / "analytics.old.jsonl"));
    CHECK(fs::file_size(scratch.file) > limit);
  }
}

static void test_two_threads_share_a_log() {
  // The engine thread records while the UI thread rates and asks for the summary: every line arrives whole.
  Scratch scratch;
  AnalyticsLog log(scratch.file);
  log.record(state("connecting"));
  log.record(state("ready"));
  const int turns = 200;
  std::thread engine([&] {
    for (int id = 1; id <= turns; id++) turn(log, id, 1000 + id, "x", "y");
  });
  for (int id = 1; id <= turns; id++) {
    log.rate("out", id, id % 2 == 0 ? "good" : "bad");
    if (id % 40 == 0) CHECK(log.summary().is_object());
    if (id % 50 == 0) log.set_enabled(log.enabled());
  }
  engine.join();
  const Json summary = log.summary();
  CHECK(number(summary, "turns") == turns);
  CHECK(number(summary, "ratedGood") == turns / 2);
  CHECK(number(summary, "ratedBad") == turns / 2);
  const auto written = lines(scratch.file);
  CHECK(written.size() == static_cast<std::size_t>(1 + 2 * turns));
  int whole = 0;
  Json value;
  for (const std::string& line : written) whole += Json::parse(line, value) && value.is_object() ? 1 : 0;
  CHECK(whole == 1 + 2 * turns);
}

int main() {
  test_records_numbers_only_and_summarises_them();
  test_mock_sessions_are_kept_out_of_the_figures();
  test_disabled_log_writes_nothing_and_clear_removes_the_file();
  test_session_numbers_continue_across_launches_and_clear();
  test_record_shapes_match_the_telemetry_contract();
  test_timestamps_are_utc_with_milliseconds();
  test_keys_of_a_written_line_are_sorted();
  test_caption_length_is_counted_in_code_points();
  test_summary_of_an_existing_log();
  test_ignores_what_it_cannot_use();
  test_a_full_log_is_set_aside();
  test_two_threads_share_a_log();
  return livebridge_test::finish();
}
