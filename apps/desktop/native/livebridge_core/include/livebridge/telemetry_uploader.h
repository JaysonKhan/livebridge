// Opt-in upload of the numbers-only analytics log to the developer's collector, and feedback submission: the C++
// twin of the Swift TelemetryUploader. Wire contract: docs/telemetry-api.md.
//
// Nothing is sent unless `set_enabled(true)` was called (default off); feedback is sent only when the user submits
// it. The uploader reads the file `AnalyticsLog` writes, so it can only ever send what that log holds — timings,
// counts, codes, text lengths, ratings. It remembers (in the injected store) how far it has uploaded and resumes
// there; a failed upload is retried the next time `upload_pending` is called, never queued in memory.
//
// The platform pieces are injected: an HTTP POST function, a small key–value store, the app and OS versions and a
// random-UUID generator.
//
// Threads: every method is synchronous and may be called from any thread; one mutex guards the state, and it is
// not held while a request is on the network, so `status()` and `set_enabled()` answer at once during an upload.
// `upload_pending()` and `send_feedback()` block on the network (each request bounded by the HTTP function's own
// time-outs): call them on a worker thread, never on the UI thread. `status()` reads the whole log file.
#pragma once

#include <chrono>
#include <cstddef>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "livebridge/json.h"

namespace livebridge {

/// What the injected HTTP function reports: the status code of the answer, or 0 when no answer came (offline, name
/// not resolved, TLS failure, time-out, cancelled). The answer's body is not needed.
struct HttpResponse {
  int status = 0;
};

/// Where the uploader keeps its three values (install id, upload offset, last upload time) between launches. A key
/// that was never set reads as "". Called only under the uploader's mutex.
class KeyValueStore {
 public:
  virtual ~KeyValueStore() = default;
  virtual std::string get(const std::string& key) const = 0;
  virtual void set(const std::string& key, const std::string& value) = 0;
};

class TelemetryUploader {
 public:
  /// POSTs `json_body` to `url` with `Content-Type: application/json`, without cookies or stored credentials, and
  /// reports the answer's status code (0 = no answer).
  using Http = std::function<HttpResponse(const std::string& url, const std::string& json_body)>;
  using Clock = std::function<std::chrono::system_clock::time_point()>;

  static constexpr const char* kDefaultEndpoint = "https://jaysonkhan.com/api/services/v1";
  /// Store keys: the macOS UserDefaults keys.
  static constexpr const char* kInstallIdKey = "livebridge.telemetry.installId";
  static constexpr const char* kOffsetKey = "livebridge.telemetry.offset";
  static constexpr const char* kLastUploadAtKey = "livebridge.telemetry.lastUploadAt";
  /// The collector takes at most this many records per request.
  static constexpr std::size_t kBatchSize = 500;

  struct Options {
    /// The AnalyticsLog file (its `path()`).
    std::filesystem::path log_file;
    /// The collector's base URL, without a trailing slash; "" means kDefaultEndpoint. The app passes the
    /// `telemetryEndpoint` preference here when it is a non-empty string (forks and tests point it elsewhere).
    std::string endpoint;
    /// `app_version` of both requests, e.g. "1.0.0+1" (on Windows the FLUTTER_VERSION definition).
    std::string app_version;
    /// `os_version` of uploads, e.g. "Windows 11 (build 26100)".
    std::string os_version;
    /// Required.
    Http http;
    /// Required.
    std::shared_ptr<KeyValueStore> store;
    /// A random UUID v4 in its usual text form; asked once, when sharing is first switched on (lower-cased here).
    std::function<std::string()> new_uuid;
    /// Stamps `lastUploadAt`; null means the system clock. Replaced in tests only.
    Clock clock;
  };

  explicit TelemetryUploader(Options options);

  TelemetryUploader(const TelemetryUploader&) = delete;
  TelemetryUploader& operator=(const TelemetryUploader&) = delete;

  /// The user's "Share anonymous statistics" switch (preference `telemetryEnabled`). Switching on creates the random
  /// install id (once, kept for good); switching off only stops uploading, and an upload in progress stops before
  /// its next batch.
  bool enabled() const;
  void set_enabled(bool on);

  /// Interface language reported with uploads and feedback (`uz`, `ru`, `tr`, `en`); "" leaves it out.
  void set_ui_language(std::string language);

  /// The bridge's `telemetryStatus` map (docs/bridge-contract.md): `enabled`, `endpoint`, `pendingRecords`, and,
  /// when known, `installId`, `lastUploadAt` (ISO-8601 UTC, whole seconds) and `lastError`.
  Json status() const;

  /// Uploads whatever the log gained since the last successful upload, in batches of at most kBatchSize records.
  /// Returns the number of records the collector accepted: 0 when switched off, when there is nothing new, when
  /// another upload is already running, or when the upload failed (`lastError` then says why). Records of mock
  /// sessions are skipped. 400 / 413 skip the batch; 429, 5xx and no answer keep the position for next time.
  int upload_pending();

  /// Sends the user's feedback: the message, the e-mail only when one was typed ("" = none), the rating only when
  /// given, and the install id only while sharing is switched on. Returns "" when the collector took it, otherwise
  /// the bridge's PlatformException code: "rate_limited" (429), "feedback_rejected" (400, 413) or "feedback_failed"
  /// (anything else, no answer included). Nothing is queued.
  std::string send_feedback(const std::string& message, const std::string& email, std::optional<int> rating);

  /// The bridge's check of `sendFeedback`'s `message` before it calls send_feedback (on macOS in the Runner): white
  /// space around it removed, then 1–2000 characters (Unicode code points; only ASCII white space is trimmed).
  /// nullopt: answer `bad_arguments`.
  static std::optional<std::string> feedback_message(const std::string& raw);

 private:
  struct Pending {
    /// Every uploadable record after the stored offset.
    std::size_t count = 0;
    /// The first `keep` of them (the "mock" flag removed), and the offset just past each one's line.
    std::vector<Json> records;
    std::vector<std::size_t> ends;
    /// Just past the last complete line looked at.
    std::size_t scanned_to = 0;
  };

  /// Reads the log from the stored offset. Caller holds mutex_.
  Pending pending(std::size_t keep) const;
  /// POSTs to `<endpoint>/<path>` and returns the status code (0 = no answer). Called without mutex_.
  int post(const char* path, const std::string& body) const;

  const std::filesystem::path log_file_;
  const std::string endpoint_;
  const std::string app_version_;
  const std::string os_version_;
  const Http http_;
  const std::shared_ptr<KeyValueStore> store_;
  const std::function<std::string()> new_uuid_;
  const Clock clock_;

  mutable std::mutex mutex_;
  bool enabled_ = false;
  bool uploading_ = false;
  std::string ui_language_;
  std::optional<std::string> last_error_;
};

}  // namespace livebridge
