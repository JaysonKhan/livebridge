#include "win_telemetry.h"

#include <windows.h>

#include <objbase.h>
#include <winhttp.h>

#include <cstddef>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <system_error>
#include <utility>

#include "win_util.h"

namespace {

// Resolving the name, connecting, sending and waiting for the answer each get this long.
const int kTimeoutMs = 10'000;
// WinHttpCrackUrl: "give me a pointer into the URL for this part".
const DWORD kPartOfUrl = static_cast<DWORD>(-1);
const wchar_t kJsonHeader[] = L"Content-Type: application/json\r\n";
// WinHttpSendRequest: the headers are a null-terminated string.
const DWORD kNullTerminated = static_cast<DWORD>(-1);
// The first build number of Windows 11.
const DWORD kFirstWindows11Build = 22000;

}  // namespace

// ── WinHttpPoster ──

WinHttpPoster::~WinHttpPoster() { CloseAll(); }

livebridge::HttpResponse WinHttpPoster::Post(const std::string& url, const std::string& json_body) {
  livebridge::HttpResponse response;
  const std::wstring wide_url = Utf16FromUtf8(url);
  URL_COMPONENTS parts = {};
  parts.dwStructSize = static_cast<DWORD>(sizeof(parts));
  parts.dwSchemeLength = kPartOfUrl;
  parts.dwHostNameLength = kPartOfUrl;
  parts.dwUrlPathLength = kPartOfUrl;
  parts.dwExtraInfoLength = kPartOfUrl;
  if (wide_url.empty() || json_body.size() > static_cast<std::size_t>(MAXDWORD) ||
      !::WinHttpCrackUrl(wide_url.c_str(), static_cast<DWORD>(wide_url.size()), 0, &parts) ||
      parts.lpszHostName == nullptr || parts.dwHostNameLength == 0 ||
      (parts.nScheme != INTERNET_SCHEME_HTTP && parts.nScheme != INTERNET_SCHEME_HTTPS)) {
    return response;
  }
  const bool secure = parts.nScheme == INTERNET_SCHEME_HTTPS;
  const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
  // The path exactly as given (the collector needs its trailing slash), with any query after it.
  std::wstring path;
  if (parts.lpszUrlPath != nullptr) path.assign(parts.lpszUrlPath, parts.dwUrlPathLength);
  if (parts.lpszExtraInfo != nullptr) path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
  if (path.empty()) path = L"/";

  // A session per request: no cookie or connection outlives it.
  const HINTERNET session = ::WinHttpOpen(L"LiveBridge", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME,
                                          WINHTTP_NO_PROXY_BYPASS, 0);
  if (!Keep(session_, session) || !::WinHttpSetTimeouts(session, kTimeoutMs, kTimeoutMs, kTimeoutMs, kTimeoutMs)) {
    CloseAll();
    return response;
  }
  const HINTERNET connection = ::WinHttpConnect(session, host.c_str(), parts.nPort, 0);
  if (!Keep(connection_, connection)) {
    CloseAll();
    return response;
  }
  const DWORD secure_flag = secure ? static_cast<DWORD>(WINHTTP_FLAG_SECURE) : 0;
  const HINTERNET request = ::WinHttpOpenRequest(connection, L"POST", path.c_str(), nullptr, WINHTTP_NO_REFERER,
                                                 WINHTTP_DEFAULT_ACCEPT_TYPES, secure_flag);
  if (!Keep(request_, request)) {
    CloseAll();
    return response;
  }

  // No cookies travel with telemetry (and WinHTTP sends no stored credentials unless asked to).
  DWORD no_cookies = WINHTTP_DISABLE_COOKIES;
  const DWORD no_cookies_size = static_cast<DWORD>(sizeof(no_cookies));
  DWORD answer = 0;
  DWORD answer_size = static_cast<DWORD>(sizeof(answer));
  const DWORD body_size = static_cast<DWORD>(json_body.size());
  const bool answered =
      ::WinHttpSetOption(request, WINHTTP_OPTION_DISABLE_FEATURE, &no_cookies, no_cookies_size) &&
      ::WinHttpSendRequest(request, kJsonHeader, kNullTerminated, const_cast<char*>(json_body.data()), body_size,
                           body_size, 0) &&
      ::WinHttpReceiveResponse(request, nullptr) &&
      ::WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                            WINHTTP_HEADER_NAME_BY_INDEX, &answer, &answer_size, WINHTTP_NO_HEADER_INDEX);
  if (answered) response.status = static_cast<int>(answer);
  CloseAll();
  return response;
}

void WinHttpPoster::Cancel() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    cancelled_ = true;
  }
  // Closing a handle cancels the call the worker thread is blocked in on it.
  CloseAll();
}

bool WinHttpPoster::Keep(Handle& slot, Handle handle) {
  if (handle == nullptr) return false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!cancelled_) {
      slot = handle;
      return true;
    }
  }
  ::WinHttpCloseHandle(handle);
  return false;
}

void WinHttpPoster::CloseAll() {
  Handle handles[3] = {nullptr, nullptr, nullptr};
  {
    std::lock_guard<std::mutex> lock(mutex_);
    // Children first: the order WinHTTP wants its handles closed in.
    handles[0] = request_;
    handles[1] = connection_;
    handles[2] = session_;
    request_ = nullptr;
    connection_ = nullptr;
    session_ = nullptr;
  }
  for (const Handle handle : handles) {
    if (handle != nullptr) ::WinHttpCloseHandle(handle);
  }
}

// ── TelemetryFileStore ──

TelemetryFileStore::TelemetryFileStore(std::filesystem::path file) : file_(std::move(file)) {}

livebridge::Json TelemetryFileStore::Load() const {
  std::ifstream in(file_, std::ios::binary);
  std::stringstream text;
  text << in.rdbuf();
  livebridge::Json saved;
  if (!livebridge::Json::parse(text.str(), saved) || !saved.is_object()) saved = livebridge::Json::Object{};
  return saved;
}

std::string TelemetryFileStore::get(const std::string& key) const {
  std::lock_guard<std::mutex> lock(mutex_);
  const livebridge::Json saved = Load();
  const livebridge::Json* value = saved.find(key);
  return value != nullptr ? value->as_string() : std::string();
}

void TelemetryFileStore::set(const std::string& key, const std::string& value) {
  std::lock_guard<std::mutex> lock(mutex_);
  livebridge::Json saved = Load();
  saved.set(key, value);
  std::error_code ignored;
  std::filesystem::create_directories(file_.parent_path(), ignored);
  // Written beside the file and renamed over it, so a crash never leaves half an object.
  std::filesystem::path temporary = file_;
  temporary += L".tmp";
  {
    std::ofstream out(temporary, std::ios::binary | std::ios::trunc);
    out << saved.dump();
  }
  std::filesystem::rename(temporary, file_, ignored);
  if (ignored) std::filesystem::remove(temporary, ignored);
}

// ── System facts ──

std::string WindowsVersionText() {
  // RtlGetVersion reports the real version; GetVersionExW is deprecated and answers what the manifest declares.
  using RtlGetVersionFunction = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  const HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) return "Windows";
  const auto rtl_get_version = reinterpret_cast<RtlGetVersionFunction>(::GetProcAddress(ntdll, "RtlGetVersion"));
  if (rtl_get_version == nullptr) return "Windows";
  RTL_OSVERSIONINFOW info = {};
  info.dwOSVersionInfoSize = static_cast<DWORD>(sizeof(info));
  if (rtl_get_version(&info) != 0) return "Windows";
  const DWORD build = info.dwBuildNumber;
  return std::string(build >= kFirstWindows11Build ? "Windows 11" : "Windows 10") + " (build " +
         std::to_string(build) + ")";
}

std::string NewUuidText() {
  GUID guid = {};
  if (FAILED(::CoCreateGuid(&guid))) return std::string();
  char text[40];
  std::snprintf(text, sizeof(text), "%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                static_cast<unsigned long>(guid.Data1), static_cast<unsigned>(guid.Data2),
                static_cast<unsigned>(guid.Data3), static_cast<unsigned>(guid.Data4[0]),
                static_cast<unsigned>(guid.Data4[1]), static_cast<unsigned>(guid.Data4[2]),
                static_cast<unsigned>(guid.Data4[3]), static_cast<unsigned>(guid.Data4[4]),
                static_cast<unsigned>(guid.Data4[5]), static_cast<unsigned>(guid.Data4[6]),
                static_cast<unsigned>(guid.Data4[7]));
  return text;
}

// ── WinTelemetry ──

WinTelemetry::WinTelemetry(const std::filesystem::path& log_file, const std::string& app_version,
                           const std::string& endpoint)
    : http_(std::make_shared<WinHttpPoster>()) {
  livebridge::TelemetryUploader::Options options;
  options.log_file = log_file;
  options.endpoint = endpoint;
  options.app_version = app_version;
  options.os_version = WindowsVersionText();
  const std::shared_ptr<WinHttpPoster> poster = http_;
  options.http = [poster](const std::string& url, const std::string& json_body) {
    return poster->Post(url, json_body);
  };
  options.store = std::make_shared<TelemetryFileStore>(AppDataFolder() / L"telemetry.json");
  options.new_uuid = NewUuidText;
  uploader_ = std::make_unique<livebridge::TelemetryUploader>(std::move(options));
  worker_ = std::thread([this] { Run(); });
}

WinTelemetry::~WinTelemetry() {
  std::deque<std::function<void()>> dropped;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stopping_ = true;
    dropped.swap(tasks_);
  }
  http_->Cancel();
  wake_.notify_all();
  if (worker_.joinable()) worker_.join();
}

void WinTelemetry::UploadPending() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopping_ || upload_queued_) return;
    upload_queued_ = true;
    tasks_.push_back([this] {
      {
        std::lock_guard<std::mutex> guard(mutex_);
        upload_queued_ = false;
      }
      uploader_->upload_pending();
    });
  }
  wake_.notify_one();
}

void WinTelemetry::SendFeedback(std::string message, std::string email, std::optional<int> rating,
                                FeedbackDone done) {
  Enqueue([this, text = std::move(message), address = std::move(email), stars = rating, reply = std::move(done)] {
    const std::string code = uploader_->send_feedback(text, address, stars);
    {
      std::lock_guard<std::mutex> guard(mutex_);
      // Cut short by the destructor: nobody is waiting any more.
      if (stopping_) return;
    }
    if (reply) reply(code);
  });
}

void WinTelemetry::SetEnabled(bool on) { uploader_->set_enabled(on); }

void WinTelemetry::SetUiLanguage(std::string language) { uploader_->set_ui_language(std::move(language)); }

livebridge::Json WinTelemetry::Status() const { return uploader_->status(); }

void WinTelemetry::Enqueue(std::function<void()> task) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopping_) return;
    tasks_.push_back(std::move(task));
  }
  wake_.notify_one();
}

void WinTelemetry::Run() {
  std::unique_lock<std::mutex> lock(mutex_);
  for (;;) {
    wake_.wait(lock, [this] { return stopping_ || !tasks_.empty(); });
    if (stopping_) return;
    std::function<void()> task = std::move(tasks_.front());
    tasks_.pop_front();
    lock.unlock();
    task();
    lock.lock();
  }
}
