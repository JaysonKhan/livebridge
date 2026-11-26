#include "gateway_socket.h"

#include <windows.h>

#include <winhttp.h>

#include <algorithm>
#include <utility>
#include <vector>

#include "livebridge/json.h"
#include "win_util.h"

namespace {

// Name resolution, connecting, sending and waiting for an HTTP answer each get this long, so that a dead gateway is
// reported instead of waited for.
const int kTimeoutMs = 10'000;
// The protocol allows 25 capture frames (500 ms) to wait for the network.
const int kMaxPendingBinary = 25;
const std::size_t kMaxMessageBytes = 512 * 1024;
const std::size_t kMaxTokenAnswerBytes = 64 * 1024;
const DWORD kChunkBytes = 16 * 1024;
// WinHttpCrackUrl: "give me a pointer into the URL for this part".
const DWORD kPartOfUrl = static_cast<DWORD>(-1);
// The longest reason a WebSocket close frame can carry.
const DWORD kMaxCloseReasonBytes = 123;

std::string WinHttpFailure(const char* what, DWORD error) {
  return std::string(what) + " (WinHTTP error " + std::to_string(error) + ")";
}

// Reads the rest of a response body. False when reading fails or the body is larger than a token answer can be.
bool ReadBody(HINTERNET request, std::string& body) {
  std::vector<char> chunk(kChunkBytes);
  for (;;) {
    DWORD waiting = 0;
    DWORD taken = 0;
    if (!::WinHttpQueryDataAvailable(request, &waiting)) return false;
    if (waiting == 0) return true;
    if (!::WinHttpReadData(request, chunk.data(), std::min(waiting, kChunkBytes), &taken)) return false;
    if (taken == 0) return true;
    body.append(chunk.data(), taken);
    if (body.size() > kMaxTokenAnswerBytes) return false;
  }
}

// The `token` of the `/v1/sessions` answer; false when the body is not that.
bool SessionToken(const std::string& body, std::string& token) {
  livebridge::Json answer;
  if (!livebridge::Json::parse(body, answer)) return false;
  const livebridge::Json* member = answer.find("token");
  if (member == nullptr || !member->is_string() || member->as_string().empty()) return false;
  token = member->as_string();
  return true;
}

}  // namespace

GatewaySocket::GatewaySocket(std::string base_url, livebridge::SessionRequest request, Events events)
    : base_url_(std::move(base_url)), session_request_(std::move(request)), events_(std::move(events)) {
  receiver_ = std::thread([this] { Run(); });
  sender_ = std::thread([this] { SendLoop(); });
}

GatewaySocket::~GatewaySocket() { Close(); }

void GatewaySocket::SendText(std::string text) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (closing_ || closed_reported_) return;
    outgoing_.push_back(Outgoing{false, std::move(text)});
  }
  wake_.notify_all();
}

bool GatewaySocket::SendBinary(const std::uint8_t* data, std::size_t size) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    // On a connection that has ended nothing is sent, but that is not the network falling behind.
    if (closing_ || closed_reported_) return true;
    if (pending_binary_ >= kMaxPendingBinary) return false;
    pending_binary_++;
    outgoing_.push_back(Outgoing{true, std::string(reinterpret_cast<const char*>(data), size)});
  }
  wake_.notify_all();
  return true;
}

void GatewaySocket::Close() {
  Handle handles[4] = {nullptr, nullptr, nullptr, nullptr};
  bool say_goodbye = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    closing_ = true;
    say_goodbye = websocket_ != nullptr && !closed_reported_;
    // Children first: that is the order WinHTTP wants its handles closed in.
    handles[0] = websocket_;
    handles[1] = request_;
    handles[2] = connection_;
    handles[3] = session_;
    websocket_ = nullptr;
    request_ = nullptr;
    connection_ = nullptr;
    session_ = nullptr;
  }
  wake_.notify_all();

  // A close frame for the gateway, without waiting for its answer (WinHttpWebSocketClose would wait, up to its own
  // time-out, and this is the engine thread). It fails when a send is in flight; the handle is closed regardless.
  if (say_goodbye) {
    ::WinHttpWebSocketShutdown(handles[0], static_cast<USHORT>(WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS), nullptr, 0);
  }
  // Closing a handle cancels the call another thread is blocked in on it: this is what ends both threads.
  for (const Handle handle : handles) {
    if (handle != nullptr) ::WinHttpCloseHandle(handle);
  }
  if (receiver_.joinable()) receiver_.join();
  if (sender_.joinable()) sender_.join();
}

bool GatewaySocket::Keep(Handle& slot, Handle handle) {
  if (handle == nullptr) return false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!closing_) {
      slot = handle;
      handle = nullptr;
    }
  }
  if (handle != nullptr) {
    ::WinHttpCloseHandle(handle);
    return false;
  }
  wake_.notify_all();
  return true;
}

void GatewaySocket::Release(Handle& slot) {
  Handle handle = nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    std::swap(handle, slot);
  }
  if (handle != nullptr) ::WinHttpCloseHandle(handle);
}

bool GatewaySocket::IsClosing() {
  std::lock_guard<std::mutex> lock(mutex_);
  return closing_;
}

void GatewaySocket::ReportClosed(const std::string& code, const std::string& reason) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (closing_ || closed_reported_) return;
    closed_reported_ = true;
  }
  wake_.notify_all();
  // Outside the lock: the callback posts to the engine thread, which may be inside Close() waiting for us.
  events_.closed(code, reason);
}

void GatewaySocket::Run() {
  Handle websocket = nullptr;
  std::string code;
  std::string reason;
  if (!Connect(websocket, code, reason)) {
    ReportClosed(code, reason);
    return;
  }
  if (IsClosing()) return;
  events_.opened();
  Receive(websocket);
}

bool GatewaySocket::Connect(Handle& websocket, std::string& code, std::string& reason) {
  // Until the gateway has answered, whatever goes wrong means it could not be reached.
  code = "gateway_unreachable";

  const std::wstring url = Utf16FromUtf8(base_url_);
  URL_COMPONENTS parts = {};
  parts.dwStructSize = static_cast<DWORD>(sizeof(parts));
  parts.dwSchemeLength = kPartOfUrl;
  parts.dwHostNameLength = kPartOfUrl;
  parts.dwUrlPathLength = kPartOfUrl;
  parts.dwExtraInfoLength = kPartOfUrl;
  if (url.empty() || !::WinHttpCrackUrl(url.c_str(), static_cast<DWORD>(url.size()), 0, &parts) ||
      parts.lpszHostName == nullptr || parts.dwHostNameLength == 0) {
    code = "gateway_error";
    reason = "invalid gateway URL";
    return false;
  }
  const bool secure = parts.nScheme == INTERNET_SCHEME_HTTPS;
  const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
  // A gateway behind a reverse proxy may live under a path: it stays in front of both endpoints.
  std::wstring prefix;
  if (parts.lpszUrlPath != nullptr) prefix.assign(parts.lpszUrlPath, parts.dwUrlPathLength);
  while (!prefix.empty() && prefix.back() == L'/') prefix.pop_back();

  const HINTERNET session = ::WinHttpOpen(L"LiveBridge", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME,
                                          WINHTTP_NO_PROXY_BYPASS, 0);
  if (!Keep(session_, session)) {
    reason = WinHttpFailure("WinHTTP could not be started", ::GetLastError());
    return false;
  }
  // The last one is the time-out for receiving, and 0 means none: on the WebSocket minutes of silence are normal,
  // and whichever handle it takes that setting from, this one or its request, must not end it. The two HTTP
  // exchanges are bounded in Exchange().
  if (!::WinHttpSetTimeouts(session, kTimeoutMs, kTimeoutMs, kTimeoutMs, 0)) {
    reason = WinHttpFailure("WinHTTP refused the time-outs", ::GetLastError());
    return false;
  }
  const HINTERNET connection = ::WinHttpConnect(session, host.c_str(), parts.nPort, 0);
  if (!Keep(connection_, connection)) {
    reason = WinHttpFailure("the gateway address was refused", ::GetLastError());
    return false;
  }

  // 1. The session request (a static or account token, or the user's own provider keys) buys a short-lived session
  //    token.
  DWORD status = 0;
  HINTERNET request = Exchange(connection, L"POST", prefix + L"/v1/sessions", secure, session_request_.bearer,
                               session_request_.body, false, status, reason);
  if (request == nullptr) return false;
  std::string body;
  std::string session_token;
  // The answer is read whatever its status: a refusal names its reason there.
  const bool body_read = ReadBody(request, body);
  const bool accepted = status == 201 && body_read && SessionToken(body, session_token);
  Release(request_);
  if (!accepted) {
    const livebridge::HostError refusal = livebridge::session_refusal(status, body_read ? body : std::string());
    code = refusal.code;
    reason = refusal.message;
    return false;
  }

  // 2. The realtime WebSocket, opened with the session token.
  request = Exchange(connection, L"GET", prefix + L"/v1/realtime", secure, session_token, std::string(), true, status,
                     reason);
  if (request == nullptr) return false;
  if (status != 101) {
    Release(request_);
    reason = "the gateway refused the realtime connection (HTTP " + std::to_string(status) + ")";
    return false;
  }
  const HINTERNET upgraded = ::WinHttpWebSocketCompleteUpgrade(request, 0);
  const DWORD upgrade_error = ::GetLastError();
  // The request has done its work: from here the WebSocket handle carries the connection.
  Release(request_);
  if (!Keep(websocket_, upgraded)) {
    reason = WinHttpFailure("the realtime connection could not be opened", upgrade_error);
    return false;
  }
  websocket = upgraded;
  return true;
}

// Sends `verb path` — with a bearer token unless `bearer` is empty, and with `body` as JSON unless it is empty — and
// waits for the status line of the answer. The request is returned, and stays in `request_` so that Close() can
// cancel it; null, with `reason` set, when no answer came.
GatewaySocket::Handle GatewaySocket::Exchange(Handle connection, const wchar_t* verb, const std::wstring& path,
                                              bool secure, const std::string& bearer, const std::string& body,
                                              bool upgrade, unsigned long& status, std::string& reason) {
  const DWORD flags = secure ? static_cast<DWORD>(WINHTTP_FLAG_SECURE) : 0;
  const HINTERNET request = ::WinHttpOpenRequest(connection, verb, path.c_str(), nullptr, WINHTTP_NO_REFERER,
                                                 WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
  if (!Keep(request_, request)) {
    reason = WinHttpFailure("the request could not be created", ::GetLastError());
    return nullptr;
  }

  const std::wstring authorization = L"Authorization: Bearer " + Utf16FromUtf8(bearer);
  const std::wstring content_type = L"Content-Type: application/json";
  // WinHTTP reads the body while sending; `body` outlives this call, and the answer arrives before it returns.
  void* const data = body.empty() ? nullptr : static_cast<void*>(const_cast<char*>(body.data()));
  const DWORD data_size = static_cast<DWORD>(body.size());
  DWORD answer_timeout = static_cast<DWORD>(kTimeoutMs);
  DWORD status_size = static_cast<DWORD>(sizeof(status));
  // A plain request gets a time-out for receiving too. The WebSocket request keeps "none" (see Connect), so only
  // the answer to the upgrade itself is given a limit.
  const bool prepared =
      upgrade ? ::WinHttpSetOption(request, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, nullptr, 0) &&
                    ::WinHttpSetOption(request, WINHTTP_OPTION_RECEIVE_RESPONSE_TIMEOUT, &answer_timeout,
                                       static_cast<DWORD>(sizeof(answer_timeout)))
              : ::WinHttpSetTimeouts(request, kTimeoutMs, kTimeoutMs, kTimeoutMs, kTimeoutMs) != FALSE;
  const bool answered =
      prepared &&
      (bearer.empty() ||
       ::WinHttpAddRequestHeaders(request, authorization.c_str(), static_cast<DWORD>(authorization.size()),
                                  WINHTTP_ADDREQ_FLAG_ADD)) &&
      (body.empty() ||
       ::WinHttpAddRequestHeaders(request, content_type.c_str(), static_cast<DWORD>(content_type.size()),
                                  WINHTTP_ADDREQ_FLAG_ADD)) &&
      ::WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, data, data_size, data_size, 0) &&
      ::WinHttpReceiveResponse(request, nullptr) &&
      ::WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                            WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size, WINHTTP_NO_HEADER_INDEX);
  if (!answered) {
    reason = WinHttpFailure("no response from the gateway", ::GetLastError());
    Release(request_);
    return nullptr;
  }
  return request;
}

void GatewaySocket::Receive(Handle websocket) {
  std::string message;
  std::vector<char> chunk(kChunkBytes);
  for (;;) {
    DWORD taken = 0;
    WINHTTP_WEB_SOCKET_BUFFER_TYPE kind = WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE;
    const DWORD error = ::WinHttpWebSocketReceive(websocket, chunk.data(), kChunkBytes, &taken, &kind);
    if (error != ERROR_SUCCESS) {
      ReportClosed("gateway_unreachable", WinHttpFailure("the connection to the gateway was lost", error));
      return;
    }
    if (kind == WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE) {
      USHORT close_status = 0;
      char close_reason[kMaxCloseReasonBytes];
      DWORD close_reason_bytes = 0;
      std::string reason = "the gateway closed the connection";
      if (::WinHttpWebSocketQueryCloseStatus(websocket, &close_status, close_reason, kMaxCloseReasonBytes,
                                             &close_reason_bytes) == ERROR_SUCCESS) {
        reason += " (" + std::to_string(close_status) + ")";
      }
      ReportClosed("gateway_unreachable", reason);
      return;
    }
    if (message.size() + taken > kMaxMessageBytes) {
      ReportClosed("gateway_error", "the gateway sent a message larger than 512 KiB");
      return;
    }
    message.append(chunk.data(), taken);
    // A fragment: the buffer was smaller than the message, the rest follows.
    if (kind == WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE ||
        kind == WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE) {
      continue;
    }
    const bool binary = kind == WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE;
    if (IsClosing()) return;
    events_.message(binary, std::move(message));
    message.clear();
  }
}

void GatewaySocket::SendLoop() {
  std::unique_lock<std::mutex> lock(mutex_);
  for (;;) {
    wake_.wait(lock, [this] {
      return closing_ || closed_reported_ || (websocket_ != nullptr && !outgoing_.empty());
    });
    if (closing_ || closed_reported_) return;
    Outgoing next = std::move(outgoing_.front());
    outgoing_.pop_front();
    const Handle websocket = websocket_;
    lock.unlock();

    const DWORD error = ::WinHttpWebSocketSend(
        websocket,
        next.binary ? WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE : WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE,
        next.payload.data(), static_cast<DWORD>(next.payload.size()));
    if (error != ERROR_SUCCESS) {
      ReportClosed("gateway_unreachable", WinHttpFailure("sending to the gateway failed", error));
      return;
    }

    lock.lock();
    if (next.binary) pending_binary_--;
  }
}
