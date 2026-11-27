#include "livebridge/telemetry_uploader.h"

#include <cstdio>
#include <fstream>
#include <limits>
#include <sstream>
#include <string_view>
#include <utility>

namespace livebridge {
namespace {

const std::size_t kMaxFeedbackCharacters = 2000;

/// The whole file; false when it cannot be read.
bool read_file(const std::filesystem::path& path, std::string& out) {
  std::ifstream file(path, std::ios::binary);
  if (!file) return false;
  std::ostringstream text;
  text << file.rdbuf();
  out = text.str();
  return true;
}

/// A stored offset: plain digits, or 0 (also for a missing or damaged value, like UserDefaults' `integer(forKey:)`).
std::size_t parse_offset(const std::string& text) {
  if (text.empty()) return 0;
  std::size_t value = 0;
  for (const char c : text) {
    if (c < '0' || c > '9') return 0;
    const auto digit = static_cast<std::size_t>(c - '0');
    if (value > (std::numeric_limits<std::size_t>::max() - digit) / 10) return 0;
    value = value * 10 + digit;
  }
  return value;
}

std::string lowercase(std::string text) {
  for (char& c : text)
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
  return text;
}

/// 2026-11-25T09:13:10Z: UTC, whole seconds (what Swift's ISO8601DateFormatter writes by default). The calendar
/// arithmetic is H. Hinnant's civil_from_days, so no platform time function is needed.
std::string iso8601(std::chrono::system_clock::time_point now) {
  const long long seconds =
      std::chrono::floor<std::chrono::seconds>(now.time_since_epoch()).count();
  long long days = seconds / 86400;
  long long rest = seconds % 86400;
  if (rest < 0) {
    rest += 86400;
    days--;
  }
  days += 719468;
  const long long era = (days >= 0 ? days : days - 146096) / 146097;
  const long long day_of_era = days - era * 146097;
  const long long year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
  const long long day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
  const long long shifted_month = (5 * day_of_year + 2) / 153;
  const long long day = day_of_year - (153 * shifted_month + 2) / 5 + 1;
  const long long month = shifted_month < 10 ? shifted_month + 3 : shifted_month - 9;
  const long long year = year_of_era + era * 400 + (month <= 2 ? 1 : 0);
  char buffer[64];
  std::snprintf(buffer, sizeof(buffer), "%04lld-%02lld-%02lldT%02lld:%02lld:%02lldZ", year, month, day, rest / 3600,
                rest / 60 % 60, rest % 60);
  return buffer;
}

bool is_space(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f'; }

}  // namespace

TelemetryUploader::TelemetryUploader(Options options)
    : log_file_(std::move(options.log_file)),
      endpoint_(options.endpoint.empty() ? std::string(kDefaultEndpoint) : std::move(options.endpoint)),
      app_version_(std::move(options.app_version)),
      os_version_(std::move(options.os_version)),
      http_(std::move(options.http)),
      store_(std::move(options.store)),
      new_uuid_(std::move(options.new_uuid)),
      clock_(options.clock ? std::move(options.clock) : Clock(std::chrono::system_clock::now)) {}

bool TelemetryUploader::enabled() const {
  const std::lock_guard<std::mutex> lock(mutex_);
  return enabled_;
}

void TelemetryUploader::set_enabled(bool on) {
  const std::lock_guard<std::mutex> lock(mutex_);
  enabled_ = on;
  if (on && store_->get(kInstallIdKey).empty() && new_uuid_) store_->set(kInstallIdKey, lowercase(new_uuid_()));
}

void TelemetryUploader::set_ui_language(std::string language) {
  const std::lock_guard<std::mutex> lock(mutex_);
  ui_language_ = std::move(language);
}

Json TelemetryUploader::status() const {
  const std::lock_guard<std::mutex> lock(mutex_);
  Json::Object fields{{"enabled", enabled_},
                      {"endpoint", endpoint_},
                      {"pendingRecords", static_cast<long long>(pending(0).count)},
                      {"appVersion", app_version_},
                      {"osVersion", os_version_}};
  const std::string install_id = store_->get(kInstallIdKey);
  if (!install_id.empty()) fields.emplace_back("installId", install_id);
  const std::string uploaded_at = store_->get(kLastUploadAtKey);
  if (!uploaded_at.empty()) fields.emplace_back("lastUploadAt", uploaded_at);
  if (last_error_) fields.emplace_back("lastError", *last_error_);
  return Json(std::move(fields));
}

int TelemetryUploader::upload_pending() {
  std::unique_lock<std::mutex> lock(mutex_);
  if (!enabled_ || uploading_) return 0;
  const std::string install_id = store_->get(kInstallIdKey);
  if (install_id.empty()) return 0;
  uploading_ = true;

  int total = 0;
  while (enabled_) {
    const Pending found = pending(kBatchSize);
    if (found.records.empty()) {
      // Nothing uploadable left; step over skipped (mock) lines so they are not rescanned.
      store_->set(kOffsetKey, std::to_string(found.scanned_to));
      break;
    }
    Json::Object body{{"app", "livebridge"},
                      {"schema", 1},
                      {"install_id", install_id},
                      {"app_version", app_version_},
                      {"os_version", os_version_}};
    if (!ui_language_.empty()) body.emplace_back("ui_language", ui_language_);
    body.emplace_back("records", Json::Array(found.records));
    const std::string text = Json(std::move(body)).dump();

    lock.unlock();
    const int answer = post("telemetry/", text);
    lock.lock();

    const std::string end = std::to_string(found.ends.back());
    if (answer >= 200 && answer <= 299) {
      store_->set(kOffsetKey, end);
      store_->set(kLastUploadAtKey, iso8601(clock_()));
      last_error_.reset();
      total += static_cast<int>(found.records.size());
    } else if (answer == 400 || answer == 413) {
      // The server will never accept this batch; skip it rather than block everything behind it.
      store_->set(kOffsetKey, end);
      last_error_ = "the server rejected a batch (HTTP " + std::to_string(answer) + ")";
    } else {
      // Rate limited, server error or offline: keep the position and try again next time.
      last_error_ = answer == 0 ? std::string("could not reach the server")
                                : "upload failed (HTTP " + std::to_string(answer) + ")";
      break;
    }
  }
  uploading_ = false;
  return total;
}

std::string TelemetryUploader::send_feedback(const std::string& message, const std::string& email,
                                             std::optional<int> rating) {
  std::string text;
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    Json::Object body{{"app", "livebridge"}, {"app_version", app_version_}, {"message", message}};
    if (!ui_language_.empty()) body.emplace_back("ui_language", ui_language_);
    if (!email.empty()) body.emplace_back("email", email);
    if (rating) body.emplace_back("rating", *rating);
    // The install id links feedback to statistics only when the user chose to share statistics.
    if (enabled_) {
      const std::string install_id = store_->get(kInstallIdKey);
      if (!install_id.empty()) body.emplace_back("install_id", install_id);
    }
    text = Json(std::move(body)).dump();
  }
  switch (post("feedback/", text)) {
    case 200:
    case 201:
      return std::string();
    case 429:
      return "rate_limited";
    case 400:
    case 413:
      return "feedback_rejected";
    default:
      return "feedback_failed";
  }
}

std::optional<std::string> TelemetryUploader::feedback_message(const std::string& raw) {
  std::size_t begin = 0;
  std::size_t end = raw.size();
  while (begin < end && is_space(raw[begin])) begin++;
  while (end > begin && is_space(raw[end - 1])) end--;
  std::string message = raw.substr(begin, end - begin);
  std::size_t characters = 0;
  for (const char c : message)
    if ((static_cast<unsigned char>(c) & 0xC0) != 0x80) characters++;
  if (characters == 0 || characters > kMaxFeedbackCharacters) return std::nullopt;
  return message;
}

TelemetryUploader::Pending TelemetryUploader::pending(std::size_t keep) const {
  Pending found;
  std::string data;
  if (!read_file(log_file_, data)) return found;
  std::size_t offset = parse_offset(store_->get(kOffsetKey));
  // The log was cleared or rotated: start again from its beginning.
  if (offset > data.size()) offset = 0;
  std::size_t line_start = offset;
  found.scanned_to = offset;
  Json record;
  // Only complete lines are read: a line being written has no "\n" yet.
  for (std::size_t at = offset; at < data.size(); at++) {
    if (data[at] != '\n') continue;
    const std::string_view line(data.data() + line_start, at - line_start);
    line_start = at + 1;
    found.scanned_to = line_start;
    if (!Json::parse(line, record) || !record.is_object()) continue;
    // Lines from mock sessions are skipped, but still advance the offset once nothing after them is uploadable.
    const Json* mock = record.find("mock");
    if (mock != nullptr && mock->as_bool()) continue;
    found.count++;
    if (found.records.size() >= keep) continue;
    Json::Object kept;
    for (const auto& member : record.as_object())
      if (member.first != "mock") kept.push_back(member);
    found.records.emplace_back(std::move(kept));
    found.ends.push_back(line_start);
  }
  return found;
}

int TelemetryUploader::post(const char* path, const std::string& body) const {
  // Built as a string so the trailing slash the server requires is kept exactly.
  return http_ ? http_(endpoint_ + "/" + path, body).status : 0;
}

}  // namespace livebridge
