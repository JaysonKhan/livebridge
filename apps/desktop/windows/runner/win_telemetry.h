#ifndef RUNNER_WIN_TELEMETRY_H_
#define RUNNER_WIN_TELEMETRY_H_

#include <condition_variable>
#include <deque>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include "livebridge/json.h"
#include "livebridge/telemetry_uploader.h"

// The Windows side of the opt-in statistics upload and the feedback form (docs/telemetry-api.md): the platform
// pieces livebridge::TelemetryUploader needs, and WinTelemetry, which owns the uploader and one worker thread.
//
// How the bridge (livebridge_channels.cpp) uses it — the Windows twin of what MainFlutterWindow.swift does:
//
//   Constructor, platform thread, after `analytics_` exists (`saved` = settings_store::Load()):
//     const Json* endpoint = saved.find("telemetryEndpoint");
//     telemetry_ = std::make_unique<WinTelemetry>(analytics_.path(), FLUTTER_VERSION,
//                                                 endpoint != nullptr ? endpoint->as_string() : std::string());
//     if (const Json* language = saved.find("uiLanguage")) telemetry_->SetUiLanguage(language->as_string());
//     const Json* sharing = saved.find("telemetryEnabled");
//     telemetry_->SetEnabled(sharing != nullptr && sharing->as_bool(false));
//     telemetry_->UploadPending();                              // "at app start"
//
//   `saveSettings`, before settings_store::Save():
//     const Json* language = arguments.find("uiLanguage");
//     if (language != nullptr && language->is_string()) telemetry_->SetUiLanguage(language->as_string());
//     const Json* sharing = arguments.find("telemetryEnabled");
//     if (sharing != nullptr && sharing->is_bool()) {
//       telemetry_->SetEnabled(sharing->as_bool());
//       telemetry_->UploadPending();
//     }
//
//   `telemetryStatus`:  result->Success(FromJson(telemetry_->Status()));
//
//   `sendFeedback` (std::function needs a copyable callable, so the MethodResult goes into a shared_ptr):
//     const Json* raw = arguments.find("message");
//     const auto message = livebridge::TelemetryUploader::feedback_message(
//         raw != nullptr && raw->is_string() ? raw->as_string() : std::string());
//     if (!message) return result->Error("bad_arguments", "missing or invalid arguments");
//     const Json* email = arguments.find("email");
//     const Json* rating = arguments.find("rating");
//     std::optional<int> stars;
//     if (rating != nullptr && rating->is_number()) stars = static_cast<int>(rating->as_int());
//     std::shared_ptr<flutter::MethodResult<EncodableValue>> reply = std::move(result);
//     telemetry_->SendFeedback(*message, email != nullptr && email->is_string() ? email->as_string() : "",
//                              stars, [this, reply](const std::string& code) {
//       // Worker thread: hand (reply, code) to the platform thread — queue it under a mutex and PostMessageW the
//       // window, as OnEngineEvent does with kEventsMessage — and there answer:
//       //   code.empty() ? reply->Success() : reply->Error(code, "feedback was not sent");
//     });
//
//   Upload after a session ends — in OnEngineEvent() (engine thread), right after analytics_.record(event), so the
//   session_end record is already on disk and no delay is needed (macOS waits 1 s for its queued log);
//   `session_running_` is a new bool member, engine thread only:
//     const Json* type = event.find("type");
//     const Json* phase = event.find("state");
//     if (type != nullptr && type->as_string() == "state" && phase != nullptr && phase->is_string()) {
//       const bool running = phase->as_string() != "idle";
//       if (session_running_ && !running) telemetry_->UploadPending();
//       session_running_ = running;
//     }
//
//   Lifetime: declare `telemetry_` before `host_` (the engine thread calls UploadPending until host_ is joined), and
//   in the destructor reset it right after host_.reset(), before the members its feedback callback uses.
//
// Link: winhttp.lib and ole32.lib (both already linked by the runner).

// Synchronous POST of JSON with WinHTTP, matching livebridge::TelemetryUploader::Http. One request at a time (the
// worker thread's); Cancel() may be called from any other thread.
class WinHttpPoster {
 public:
  WinHttpPoster() = default;
  ~WinHttpPoster();
  WinHttpPoster(const WinHttpPoster&) = delete;
  WinHttpPoster& operator=(const WinHttpPoster&) = delete;

  // POSTs `json_body` to `url` (http:// or https://, `Content-Type: application/json`, no cookies) with 10 s
  // time-outs for resolving, connecting, sending and waiting for the answer. Returns the status code, or 0 when no
  // answer came, the URL is not usable, or Cancel() was called.
  livebridge::HttpResponse Post(const std::string& url, const std::string& json_body);

  // Ends a Post() in progress (it returns 0) and makes every later one return 0 at once.
  void Cancel();

 private:
  using Handle = void*;

  // Keeps `handle` in `slot` so that Cancel() can close it; false (and the handle closed) after Cancel().
  bool Keep(Handle& slot, Handle handle);
  void CloseAll();

  std::mutex mutex_;
  bool cancelled_ = false;
  Handle session_ = nullptr;
  Handle connection_ = nullptr;
  Handle request_ = nullptr;
};

// livebridge::KeyValueStore in %APPDATA%\LiveBridge\telemetry.json (a JSON object of strings, its own file next to
// settings.json). Every call reads the file; `set` writes it whole. Thread-safe.
class TelemetryFileStore : public livebridge::KeyValueStore {
 public:
  explicit TelemetryFileStore(std::filesystem::path file);

  std::string get(const std::string& key) const override;
  void set(const std::string& key, const std::string& value) override;

 private:
  livebridge::Json Load() const;

  const std::filesystem::path file_;
  mutable std::mutex mutex_;
};

// "Windows 11 (build 26100)" (build 22000 and later) or "Windows 10 (build 19045)", from RtlGetVersion (which,
// unlike GetVersionExW, is not subject to manifest-based version lies). "Windows" if it cannot be asked.
std::string WindowsVersionText();

// A random UUID v4 from CoCreateGuid, lower-case with hyphens: "3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11". "" on
// failure.
std::string NewUuidText();

// Owns the uploader and one worker thread that runs uploads and feedback one after the other.
//
// Threads: every method may be called from any thread (normally the platform thread) and returns at once, except
// Status(), which reads the analytics log file. Network work happens on the worker thread, and so does the
// SendFeedback callback: Flutter's MethodResult must not be answered there — post the result to the platform
// thread. The destructor cancels a request in flight and joins the worker; queued work is dropped, and a feedback
// callback whose request was cut short this way is not called.
class WinTelemetry {
 public:
  // `code` is "" when the collector took the feedback, else "rate_limited", "feedback_rejected" or
  // "feedback_failed" (the PlatformException code for Flutter).
  using FeedbackDone = std::function<void(const std::string& code)>;

  // `log_file`: the AnalyticsLog's path(). `app_version`: e.g. FLUTTER_VERSION ("1.0.0+1"). `endpoint`: the
  // `telemetryEndpoint` preference, "" for the default collector. Sharing starts switched off: call SetEnabled().
  WinTelemetry(const std::filesystem::path& log_file, const std::string& app_version, const std::string& endpoint);
  ~WinTelemetry();
  WinTelemetry(const WinTelemetry&) = delete;
  WinTelemetry& operator=(const WinTelemetry&) = delete;

  // Queues an upload of what the log gained (a no-op on the worker unless sharing is on). Several calls before the
  // worker gets to it make one upload.
  void UploadPending();

  // Queues the user's feedback. `email` "" = none typed; `message` already checked with
  // livebridge::TelemetryUploader::feedback_message(). `done` runs on the worker thread.
  void SendFeedback(std::string message, std::string email, std::optional<int> rating, FeedbackDone done);

  // The `telemetryEnabled` preference. Switching on creates the install id; follow it with UploadPending().
  void SetEnabled(bool on);

  // Sharing on by default (no saved choice): an install that never shared sends nothing written before now.
  void EnableFromNow();

  // The `uiLanguage` preference (`uz`, `ru`, `tr`, `en`), sent with uploads and feedback.
  void SetUiLanguage(std::string language);

  // The bridge's `telemetryStatus` map; a consistent snapshot, also while an upload runs.
  livebridge::Json Status() const;

 private:
  void Enqueue(std::function<void()> task);
  void Run();

  const std::shared_ptr<WinHttpPoster> http_;
  std::unique_ptr<livebridge::TelemetryUploader> uploader_;

  std::mutex mutex_;
  std::condition_variable wake_;
  std::deque<std::function<void()>> tasks_;
  bool stopping_ = false;
  // An upload is queued and has not started yet.
  bool upload_queued_ = false;

  // Last: started at the end of the constructor, joined in the destructor.
  std::thread worker_;
};

#endif  // RUNNER_WIN_TELEMETRY_H_
