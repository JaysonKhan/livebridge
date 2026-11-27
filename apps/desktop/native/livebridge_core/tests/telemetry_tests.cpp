// Tests of the opt-in uploader: the Swift TelemetryUploaderTests (the live-collector test left out), plus what the
// C++ twin has to prove on its own (the URL, the store, torn lines, the lock left open during a request, the
// feedback message check). The log is written through the real AnalyticsLog, so an upload carries exactly what the
// app logs.
// Usage: telemetry_tests [fixture path, not used]
#include <chrono>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <random>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

#include "check.h"
#include "livebridge/analytics_log.h"
#include "livebridge/json.h"
#include "livebridge/telemetry_uploader.h"

using namespace livebridge;
namespace fs = std::filesystem;

/// A fresh directory per test, removed afterwards. The log creates it with its first line.
struct Scratch {
  fs::path dir;
  fs::path file;

  Scratch() {
    static int serial = 0;
    const std::string name = "lb-telemetry-" + std::to_string(std::random_device{}()) + "-" + std::to_string(serial++);
    dir = fs::temp_directory_path() / name;
    file = dir / "analytics.jsonl";
  }
  ~Scratch() {
    std::error_code ignored;
    fs::remove_all(dir, ignored);
  }
};

/// UserDefaults for one test.
class MemoryStore : public KeyValueStore {
 public:
  std::string get(const std::string& key) const override {
    const auto found = values.find(key);
    return found == values.end() ? std::string() : found->second;
  }
  void set(const std::string& key, const std::string& value) override { values[key] = value; }

  std::map<std::string, std::string> values;
};

/// The collector: records what was sent and answers with the queued statuses, then 202 (0 = no answer).
struct Collector {
  struct Request {
    std::string url;
    std::string text;
    Json body;
  };

  HttpResponse answer(const std::string& url, const std::string& text) {
    Request request{url, text, Json()};
    if (!Json::parse(text, request.body)) {
      livebridge_test::failures++;
      std::printf("FAILED: the uploader sent text that is not JSON: %s\n", text.c_str());
    }
    requests.push_back(std::move(request));
    if (during) {
      const std::function<void()> once = std::move(during);
      during = nullptr;
      once();
    }
    HttpResponse response;
    response.status = 202;
    if (!statuses.empty()) {
      response.status = statuses.front();
      statuses.erase(statuses.begin());
    }
    return response;
  }

  std::vector<int> statuses;
  std::vector<Request> requests;
  /// Runs once, while the next request is "on the network".
  std::function<void()> during;
};

const char* const kUuid = "3F2B6C1E-9D0A-4C1B-8F6E-2A7D5B9C0E11";

/// 2026-11-25T09:13:10.120Z
static std::chrono::system_clock::time_point morning() {
  return std::chrono::system_clock::from_time_t(1795597990) + std::chrono::milliseconds(120);
}

struct Fixture {
  Scratch scratch;
  std::shared_ptr<MemoryStore> store = std::make_shared<MemoryStore>();
  Collector collector;
  int uuids_made = 0;

  TelemetryUploader::Options options(std::string endpoint = "https://collector.test/api/services/v1") {
    TelemetryUploader::Options made;
    made.log_file = scratch.file;
    made.endpoint = std::move(endpoint);
    made.app_version = "1.2.3+4";
    made.os_version = "Windows 11 (build 26100)";
    made.http = [this](const std::string& url, const std::string& text) { return collector.answer(url, text); };
    made.store = store;
    made.new_uuid = [this] {
      uuids_made++;
      return std::string(kUuid);
    };
    made.clock = morning;
    return made;
  }
};

static Json state(const char* name, bool mock = false) {
  return Json::Object{{"type", "state"}, {"state", name}, {"mock", mock}};
}

/// One real session, written through AnalyticsLog: session_start, `turns` turns, session_end.
static void log_session(AnalyticsLog& log, int turns, bool mock = false) {
  log.record(state("connecting"));
  log.record(Json::Object{{"type", "state"}, {"state", "ready"}, {"mock", mock}, {"mode", "bidirectional"},
                          {"myLang", "uz"}, {"targetLang", "en"}, {"outCommit", "manual"}});
  for (int id = 1; id <= turns; id++) {
    log.record(Json::Object{{"type", "caption"}, {"direction", "out"}, {"turnId", id}, {"kind", "final"},
                            {"text", "Maoshim uch ming dollar"}});
    log.record(Json::Object{{"type", "metrics"}, {"direction", "out"}, {"turnId", id}, {"e2eMs", 1300},
                            {"translateTotalMs", 700}, {"sttCommitMs", 300}});
  }
  log.record(state("idle"));
}

static long long number(const Json& object, const char* key) {
  const Json* value = object.find(key);
  return value && value->is_number() ? value->as_int() : -1;
}

static std::string text_of(const Json& object, const char* key) {
  const Json* value = object.find(key);
  return value && value->is_string() ? value->as_string() : "missing";
}

static bool contains(const std::string& text, const std::string& part) { return text.find(part) != std::string::npos; }

static std::size_t records_in(const Collector::Request& request) {
  const Json* records = request.body.find("records");
  return records ? records->as_array().size() : 0;
}

// ── The Swift TelemetryUploaderTests ──

static void test_status_has_app_and_os_version() {
  Fixture fixture;
  TelemetryUploader uploader(fixture.options());
  CHECK(text_of(uploader.status(), "appVersion") == "1.2.3+4");
  CHECK(text_of(uploader.status(), "osVersion") == "Windows 11 (build 26100)");
}

// Sharing on by default (the user never chose): an install that never shared sends nothing written before.
static void test_on_by_default_sends_nothing_from_before_and_then_everything_new() {
  Fixture fixture;
  AnalyticsLog log(fixture.scratch.file);
  log_session(log, 2);
  TelemetryUploader uploader(fixture.options());
  uploader.enable_from_now();
  CHECK(uploader.enabled());
  CHECK(fixture.uuids_made == 1);
  CHECK(uploader.upload_pending() == 0);
  CHECK(fixture.collector.requests.empty());
  log_session(log, 1);
  CHECK(uploader.upload_pending() == 3);  // session_start, 1 turn, session_end
}

static void test_on_by_default_keeps_the_position_of_an_install_that_shared_before() {
  Fixture fixture;
  AnalyticsLog log(fixture.scratch.file);
  log_session(log, 2);
  TelemetryUploader uploader(fixture.options());
  uploader.set_enabled(true);
  CHECK(uploader.upload_pending() == 4);
  uploader.set_enabled(false);
  log_session(log, 1);
  uploader.enable_from_now();
  CHECK(uploader.upload_pending() == 3);
}

static void test_nothing_is_sent_until_the_user_opts_in() {
  Fixture fixture;
  AnalyticsLog log(fixture.scratch.file);
  log_session(log, 2);
  TelemetryUploader uploader(fixture.options());
  CHECK(uploader.upload_pending() == 0);
  CHECK(fixture.collector.requests.empty());
  CHECK(uploader.status().find("installId") == nullptr);
  CHECK(uploader.status().find("enabled") && !uploader.status().find("enabled")->as_bool(true));
  CHECK(!uploader.enabled());
  CHECK(fixture.uuids_made == 0);
}

static void test_uploads_numbers_only_once_and_resumes_where_it_stopped() {
  Fixture fixture;
  AnalyticsLog log(fixture.scratch.file);
  log_session(log, 2);
  TelemetryUploader uploader(fixture.options());
  uploader.set_ui_language("uz");
  uploader.set_enabled(true);
  CHECK(number(uploader.status(), "pendingRecords") == 4);  // session_start, 2 turns, session_end

  CHECK(uploader.upload_pending() == 4);
  CHECK(fixture.collector.requests.size() == 1);
  if (fixture.collector.requests.size() != 1) return;
  const Collector::Request first = fixture.collector.requests[0];
  CHECK(first.url == "https://collector.test/api/services/v1/telemetry/");
  CHECK(text_of(first.body, "app") == "livebridge");
  CHECK(number(first.body, "schema") == 1);
  CHECK(text_of(first.body, "app_version") == "1.2.3+4");
  CHECK(text_of(first.body, "ui_language") == "uz");
  CHECK(text_of(first.body, "os_version") == "Windows 11 (build 26100)");
  // A UUID v4, lower-cased, made once.
  const std::string install_id = text_of(first.body, "install_id");
  CHECK(install_id == "3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11");
  CHECK(fixture.uuids_made == 1);
  const Json* records = first.body.find("records");
  CHECK(records && records->as_array().size() == 4);
  if (!records || records->as_array().size() != 4) return;
  const Json::Array& sent = records->as_array();
  CHECK(text_of(sent[0], "type") == "session_start");
  CHECK(text_of(sent[1], "type") == "turn");
  CHECK(text_of(sent[2], "type") == "turn");
  CHECK(text_of(sent[3], "type") == "session_end");
  CHECK(text_of(sent[0], "mode") == "bidirectional");
  CHECK(number(sent[1], "e2eMs") == 1300);
  CHECK(number(sent[1], "sourceChars") == 23);
  // Privacy: the payload carries lengths and timings, never what was said, and no internal flags.
  CHECK(!contains(first.text, "Maoshim"));
  CHECK(!contains(first.text, "mock"));

  // Nothing new: nothing is sent again.
  CHECK(uploader.upload_pending() == 0);
  CHECK(fixture.collector.requests.size() == 1);
  CHECK(number(uploader.status(), "pendingRecords") == 0);
  CHECK(text_of(uploader.status(), "lastUploadAt") == "2026-11-25T09:13:10Z");

  // A later session: only its records go, under the same install id.
  log_session(log, 1);
  CHECK(uploader.upload_pending() == 3);
  CHECK(fixture.collector.requests.size() == 2);
  if (fixture.collector.requests.size() != 2) return;
  CHECK(text_of(fixture.collector.requests[1].body, "install_id") == install_id);
  CHECK(records_in(fixture.collector.requests[1]) == 3);
}

static void test_mock_sessions_are_never_uploaded() {
  Fixture fixture;
  AnalyticsLog log(fixture.scratch.file);
  log_session(log, 3, true);
  TelemetryUploader uploader(fixture.options());
  uploader.set_enabled(true);
  CHECK(number(uploader.status(), "pendingRecords") == 0);
  CHECK(uploader.upload_pending() == 0);
  CHECK(fixture.collector.requests.empty());
  // The mock lines are stepped over, so the next real session is all that is offered.
  CHECK(fixture.store->get(TelemetryUploader::kOffsetKey) == std::to_string(fs::file_size(fixture.scratch.file)));
  log_session(log, 1);
  CHECK(uploader.upload_pending() == 3);
}

static void test_failures_keep_the_position_and_permanent_rejections_do_not_block() {
  Fixture fixture;
  AnalyticsLog log(fixture.scratch.file);
  log_session(log, 1);
  TelemetryUploader uploader(fixture.options());
  uploader.set_enabled(true);

  // Rate limited, then offline: nothing is lost, the same records are offered again.
  fixture.collector.statuses = {429};
  CHECK(uploader.upload_pending() == 0);
  CHECK(number(uploader.status(), "pendingRecords") == 3);
  CHECK(text_of(uploader.status(), "lastError") == "upload failed (HTTP 429)");
  CHECK(uploader.status().find("lastUploadAt") == nullptr);
  fixture.collector.statuses = {0};
  CHECK(uploader.upload_pending() == 0);
  CHECK(number(uploader.status(), "pendingRecords") == 3);
  CHECK(text_of(uploader.status(), "lastError") == "could not reach the server");
  fixture.collector.statuses = {503};
  CHECK(uploader.upload_pending() == 0);
  CHECK(number(uploader.status(), "pendingRecords") == 3);
  CHECK(uploader.upload_pending() == 3);
  CHECK(uploader.status().find("lastError") == nullptr);
  CHECK(fixture.collector.requests.size() == 4);

  // A batch the server refuses outright is skipped, so later records still get through.
  log_session(log, 1);
  fixture.collector.statuses = {400};
  CHECK(uploader.upload_pending() == 0);
  CHECK(number(uploader.status(), "pendingRecords") == 0);
  CHECK(text_of(uploader.status(), "lastError") == "the server rejected a batch (HTTP 400)");
  log_session(log, 1);
  fixture.collector.statuses = {413};
  CHECK(uploader.upload_pending() == 0);
  CHECK(number(uploader.status(), "pendingRecords") == 0);
  log_session(log, 1);
  CHECK(uploader.upload_pending() == 3);
}

static void test_large_logs_go_in_batches_and_a_cleared_log_starts_over() {
  Fixture fixture;
  AnalyticsLog log(fixture.scratch.file);
  log_session(log, 620);  // 622 records
  TelemetryUploader uploader(fixture.options());
  uploader.set_enabled(true);
  CHECK(number(uploader.status(), "pendingRecords") == 622);
  CHECK(uploader.upload_pending() == 622);
  CHECK(fixture.collector.requests.size() == 2);
  if (fixture.collector.requests.size() != 2) return;
  CHECK(records_in(fixture.collector.requests[0]) == 500);
  CHECK(records_in(fixture.collector.requests[1]) == 122);

  log.clear();
  log_session(log, 1);
  // A shorter, new log must be read from its start.
  CHECK(uploader.upload_pending() == 3);
}

static void test_feedback_carries_only_what_the_user_typed_and_maps_server_answers() {
  Fixture fixture;
  TelemetryUploader uploader(fixture.options());
  auto send = [&](int answer, const std::string& email = "", std::optional<int> rating = std::nullopt) {
    fixture.collector.statuses = {answer};
    return uploader.send_feedback("Tez ishlaydi", email, rating);
  };
  CHECK(send(201).empty());
  CHECK(fixture.collector.requests.size() == 1);
  if (fixture.collector.requests.size() != 1) return;
  const Collector::Request anonymous = fixture.collector.requests[0];
  CHECK(anonymous.url == "https://collector.test/api/services/v1/feedback/");
  CHECK(text_of(anonymous.body, "app") == "livebridge");
  CHECK(text_of(anonymous.body, "app_version") == "1.2.3+4");
  CHECK(text_of(anonymous.body, "message") == "Tez ishlaydi");
  // Statistics sharing is off: feedback is not tied to an install, and no e-mail or rating was given.
  CHECK(anonymous.body.find("install_id") == nullptr);
  CHECK(anonymous.body.find("email") == nullptr);
  CHECK(anonymous.body.find("rating") == nullptr);
  CHECK(anonymous.body.find("ui_language") == nullptr);

  uploader.set_enabled(true);
  uploader.set_ui_language("ru");
  CHECK(send(201, "me@example.com", 4).empty());
  CHECK(fixture.collector.requests.size() == 2);
  if (fixture.collector.requests.size() != 2) return;
  CHECK(text_of(fixture.collector.requests[1].body, "install_id") == "3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11");
  CHECK(text_of(fixture.collector.requests[1].body, "email") == "me@example.com");
  CHECK(number(fixture.collector.requests[1].body, "rating") == 4);
  CHECK(text_of(fixture.collector.requests[1].body, "ui_language") == "ru");

  CHECK(send(200).empty());
  CHECK(send(429) == "rate_limited");
  CHECK(send(400) == "feedback_rejected");
  CHECK(send(413) == "feedback_rejected");
  CHECK(send(500) == "feedback_failed");
  CHECK(send(0) == "feedback_failed");

  // Sharing switched off again: the id is kept in the store, but no longer sent.
  uploader.set_enabled(false);
  CHECK(send(201).empty());
  CHECK(fixture.collector.requests.back().body.find("install_id") == nullptr);
}

// ── What the C++ twin has to prove on its own ──

static void test_status_endpoint_and_the_kept_install_id() {
  Fixture fixture;
  {
    TelemetryUploader uploader(fixture.options(""));
    const Json status = uploader.status();
    CHECK(status.dump() ==
          R"json({"enabled":false,"endpoint":"https://jaysonkhan.com/api/services/v1","pendingRecords":0,)json"
          R"json("appVersion":"1.2.3+4","osVersion":"Windows 11 (build 26100)"})json");
    CHECK(std::string(TelemetryUploader::kDefaultEndpoint) == "https://jaysonkhan.com/api/services/v1");
    uploader.set_enabled(true);
    uploader.set_enabled(false);
    uploader.set_enabled(true);
    CHECK(fixture.uuids_made == 1);
    CHECK(text_of(uploader.status(), "installId") == "3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11");
    // No log yet: nothing to send, and nothing is sent.
    CHECK(uploader.upload_pending() == 0);
    CHECK(fixture.collector.requests.empty());
  }
  {
    // The next launch: the same install, switched off until the app reads the preference.
    TelemetryUploader uploader(fixture.options("http://127.0.0.1:8011/api/services/v1"));
    CHECK(!uploader.enabled());
    CHECK(text_of(uploader.status(), "installId") == "3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11");
    CHECK(text_of(uploader.status(), "endpoint") == "http://127.0.0.1:8011/api/services/v1");
    uploader.set_enabled(true);
    CHECK(fixture.uuids_made == 1);
    AnalyticsLog log(fixture.scratch.file);
    log_session(log, 1);
    CHECK(uploader.upload_pending() == 3);
    CHECK(fixture.collector.requests.size() == 1);
    if (fixture.collector.requests.size() == 1)
      CHECK(fixture.collector.requests[0].url == "http://127.0.0.1:8011/api/services/v1/telemetry/");
  }
  {
    // A generator that failed leaves sharing on without an id: nothing is uploaded until one is made.
    Fixture broken;
    TelemetryUploader::Options options = broken.options();
    options.new_uuid = [] { return std::string(); };
    TelemetryUploader uploader(std::move(options));
    AnalyticsLog log(broken.scratch.file);
    log_session(log, 1);
    uploader.set_enabled(true);
    CHECK(uploader.status().find("installId") == nullptr);
    CHECK(uploader.upload_pending() == 0);
    CHECK(broken.collector.requests.empty());
  }
}

static void test_torn_lines_and_damaged_offsets() {
  Fixture fixture;
  AnalyticsLog log(fixture.scratch.file);
  log_session(log, 1);
  // A line still being written (no "\n" yet), and lines that are not records.
  const std::string half = R"({"mock":false,"session":1,"t":"2026-11-25T09:20:00.000Z","type":"reco)";
  {
    std::ofstream file(fixture.scratch.file, std::ios::binary | std::ios::app);
    file << "not json\n[1,2]\n\n" << half;
  }
  TelemetryUploader uploader(fixture.options());
  uploader.set_enabled(true);
  CHECK(number(uploader.status(), "pendingRecords") == 3);
  CHECK(uploader.upload_pending() == 3);
  // The offset stops in front of the torn line ...
  CHECK(fixture.store->get(TelemetryUploader::kOffsetKey) ==
        std::to_string(fs::file_size(fixture.scratch.file) - half.size()));
  {
    std::ofstream file(fixture.scratch.file, std::ios::binary | std::ios::app);
    file << R"(nnect"})" << "\n";
  }
  // ... so the finished line goes next, whole.
  CHECK(uploader.upload_pending() == 1);
  CHECK(fixture.collector.requests.size() == 2);
  if (fixture.collector.requests.size() == 2) {
    const Json* records = fixture.collector.requests[1].body.find("records");
    CHECK(records && records->as_array().size() == 1 &&
          text_of(records->as_array()[0], "type") == "reconnect");
  }

  // A damaged offset in the store counts as 0: the log is offered again from its start (the collector
  // de-duplicates).
  fixture.store->set(TelemetryUploader::kOffsetKey, "12 or so");
  CHECK(number(uploader.status(), "pendingRecords") == 4);
  fixture.store->set(TelemetryUploader::kOffsetKey, "-5");
  CHECK(number(uploader.status(), "pendingRecords") == 4);
}

static void test_the_lock_is_open_while_a_request_is_on_the_network() {
  Fixture fixture;
  AnalyticsLog log(fixture.scratch.file);
  log_session(log, 620);  // two batches
  TelemetryUploader uploader(fixture.options());
  uploader.set_enabled(true);
  int nested_upload = -1;
  bool answered = false;
  fixture.collector.during = [&] {
    // These would deadlock if the uploader kept its mutex during a request.
    answered = uploader.status().is_object();
    nested_upload = uploader.upload_pending();  // another upload is running: nothing happens
    // Switched off during the first batch: the second one is not sent.
    uploader.set_enabled(false);
  };
  CHECK(uploader.upload_pending() == 500);
  CHECK(answered);
  CHECK(nested_upload == 0);
  CHECK(fixture.collector.requests.size() == 1);
  CHECK(number(uploader.status(), "pendingRecords") == 122);
  uploader.set_enabled(true);
  CHECK(uploader.upload_pending() == 122);
}

static void test_upload_time_is_utc_whole_seconds() {
  // Around a leap day and the turn of a year, and the epoch.
  const std::pair<long long, const char*> cases[] = {
      {0, "1970-01-01T00:00:00Z"},
      {1709251199, "2024-02-29T23:59:59Z"},
      {1709251200, "2024-03-01T00:00:00Z"},
      {1798761599, "2026-12-31T23:59:59Z"},
      {1798761600, "2027-01-01T00:00:00Z"},
  };
  for (const auto& [seconds, expected] : cases) {
    Fixture fixture;
    TelemetryUploader::Options options = fixture.options();
    const auto at = std::chrono::system_clock::from_time_t(static_cast<std::time_t>(seconds)) +
                    std::chrono::milliseconds(999);
    options.clock = [at] { return at; };
    TelemetryUploader uploader(std::move(options));
    AnalyticsLog log(fixture.scratch.file);
    log_session(log, 1);
    uploader.set_enabled(true);
    CHECK(uploader.upload_pending() == 3);
    CHECK(text_of(uploader.status(), "lastUploadAt") == expected);
    if (text_of(uploader.status(), "lastUploadAt") != expected)
      std::printf("  %lld: %s\n", seconds, text_of(uploader.status(), "lastUploadAt").c_str());
  }
}

static void test_the_feedback_message_check() {
  CHECK(TelemetryUploader::feedback_message("  Tez ishlaydi\n\t") == std::optional<std::string>("Tez ishlaydi"));
  CHECK(!TelemetryUploader::feedback_message(""));
  CHECK(!TelemetryUploader::feedback_message(" \r\n\t "));
  CHECK(TelemetryUploader::feedback_message("a\n\nb") == std::optional<std::string>("a\n\nb"));
  // 2000 characters, counted in code points (two bytes each here), is the most.
  std::string longest;
  for (int i = 0; i < 2000; i++) longest += "\xD1\x8F";  // я
  CHECK(TelemetryUploader::feedback_message(" " + longest + " ") == std::optional<std::string>(longest));
  CHECK(!TelemetryUploader::feedback_message(longest + "x"));
}

int main() {
  test_status_has_app_and_os_version();
  test_on_by_default_sends_nothing_from_before_and_then_everything_new();
  test_on_by_default_keeps_the_position_of_an_install_that_shared_before();
  test_nothing_is_sent_until_the_user_opts_in();
  test_uploads_numbers_only_once_and_resumes_where_it_stopped();
  test_mock_sessions_are_never_uploaded();
  test_failures_keep_the_position_and_permanent_rejections_do_not_block();
  test_large_logs_go_in_batches_and_a_cleared_log_starts_over();
  test_feedback_carries_only_what_the_user_typed_and_maps_server_answers();
  test_status_endpoint_and_the_kept_install_id();
  test_torn_lines_and_damaged_offsets();
  test_the_lock_is_open_while_a_request_is_on_the_network();
  test_upload_time_is_utc_whole_seconds();
  test_the_feedback_message_check();
  return livebridge_test::finish();
}
