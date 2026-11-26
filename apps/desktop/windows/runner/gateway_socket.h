#ifndef RUNNER_GATEWAY_SOCKET_H_
#define RUNNER_GATEWAY_SOCKET_H_

#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>

#include "livebridge/engine.h"

// One connection to the gateway, over WinHTTP: the Windows twin of GatewayTransport.swift.
//
// Constructing it starts connecting: `POST <base>/v1/sessions` with the session request (a bearer token, a JSON body,
// or both; livebridge::session_request builds it) gives a session token, then `<base>/v1/realtime` is opened as a
// WebSocket with that token. From then on it carries JSON text messages and binary audio frames both ways.
//
// Threads: the object is created, used and closed on one thread (the engine thread). It owns two threads of its
// own, one that connects and then receives, one that sends, and calls `Events` on those. A callback must return
// quickly and must not call back into the socket: it posts to its own thread and leaves.
class GatewaySocket {
 public:
  struct Events {
    // The WebSocket is open. Called once, before any `message`.
    std::function<void()> opened;
    // One complete message: text (UTF-8 JSON) or a binary audio frame.
    std::function<void(bool binary, std::string payload)> message;
    // The connection could not be opened, or dropped, without Close() having been called. Called at most once.
    // `code` is the bridge's error code: gateway_unreachable, gateway_error, or the code of a refused session request
    // (livebridge::session_refusal).
    std::function<void(std::string code, std::string reason)> closed;
  };

  // `base_url` is `http://host[:port][/prefix]` or `https://...`. All three callbacks must be set.
  GatewaySocket(std::string base_url, livebridge::SessionRequest request, Events events);
  ~GatewaySocket();
  GatewaySocket(const GatewaySocket&) = delete;
  GatewaySocket& operator=(const GatewaySocket&) = delete;

  // Queues one text message. Text and binary messages leave in the order they were queued.
  void SendText(std::string text);
  // Queues one binary message. False when 25 of them already wait for the network: the frame is dropped then.
  bool SendBinary(const std::uint8_t* data, std::size_t size);

  // Ends the connection, whatever state it is in, and joins both threads: no callback runs after this returns.
  // Safe to call more than once; the destructor calls it too.
  void Close();

 private:
  // A WinHTTP handle (HINTERNET); spelled out so that this header needs no Windows headers.
  using Handle = void*;

  struct Outgoing {
    bool binary = false;
    std::string payload;
  };

  // The first thread: Connect(), then Receive() until the connection ends.
  void Run();
  bool Connect(Handle& websocket, std::string& code, std::string& reason);
  Handle Exchange(Handle connection, const wchar_t* verb, const std::wstring& path, bool secure,
                  const std::string& bearer, const std::string& body, bool upgrade, unsigned long& status,
                  std::string& reason);
  void Receive(Handle websocket);
  // The second thread.
  void SendLoop();

  // Handles live in the members below so that Close() can close them from the engine thread, which is how a blocked
  // WinHTTP call is cancelled. Keep() stores a new handle, or closes it and returns false when Close() has begun
  // (or the handle is null); Release() closes one that is no longer needed.
  bool Keep(Handle& slot, Handle handle);
  void Release(Handle& slot);
  bool IsClosing();
  void ReportClosed(const std::string& code, const std::string& reason);

  const std::string base_url_;
  // Lives as long as the socket: WinHTTP reads the body from here while the request is being sent.
  const livebridge::SessionRequest session_request_;
  const Events events_;

  // Guards everything below except the threads.
  std::mutex mutex_;
  // Wakes the sender: something to send, or time to leave.
  std::condition_variable wake_;
  bool closing_ = false;
  bool closed_reported_ = false;
  Handle session_ = nullptr;
  Handle connection_ = nullptr;
  Handle request_ = nullptr;
  Handle websocket_ = nullptr;
  std::deque<Outgoing> outgoing_;
  // Binary messages queued or being sent right now.
  int pending_binary_ = 0;

  std::thread receiver_;
  std::thread sender_;
};

#endif  // RUNNER_GATEWAY_SOCKET_H_
