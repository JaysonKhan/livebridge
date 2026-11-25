#ifndef RUNNER_LIVEBRIDGE_CHANNELS_H_
#define RUNNER_LIVEBRIDGE_CHANNELS_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>

#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "livebridge/analytics_log.h"
#include "livebridge/json.h"

class WinEngineHost;
class WinTelemetry;

// The Windows side of docs/bridge-contract.md: the `livebridge/control` method channel and the
// `livebridge/events` event channel.
//
// Everything in the contract is real except `languageNames`, which answers with no names (the app then uses its own
// and the English ones).
//
// Threads: Flutter's channels belong to the platform (UI) thread, and so does every method here except
// OnEngineEvent(). The audio engine lives on its own thread (win_engine_host.h); its events are queued here and
// the window is asked, with kEventsMessage, to call DrainEvents() on the platform thread.
class LiveBridgeChannels {
 public:
  // Posted to `window` whenever engine events wait; its window procedure answers by calling DrainEvents().
  static constexpr UINT kEventsMessage = WM_APP + 1;

  LiveBridgeChannels(flutter::BinaryMessenger* messenger, HWND window);
  // Stops the engine thread (closing a running session) before anything else goes away.
  ~LiveBridgeChannels();

  // Hands the queued engine events, and the answers to feedback sent in the background, to Flutter.
  void DrainEvents();

 private:
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // Engine thread: logs the event's numbers, then queues it for the platform thread.
  void OnEngineEvent(const livebridge::Json& event);
  // Any thread: asks the window for a DrainEvents() call unless one is already on its way. Takes pending_mutex_.
  void RequestDrain();

  const HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> control_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  // Where engine events go while Flutter listens. Platform thread only.
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;

  // Numbers only (timings, counts, codes); it locks for itself, so both threads may use it.
  livebridge::AnalyticsLog analytics_;

  // Engine events on their way to the platform thread.
  std::mutex pending_mutex_;
  std::vector<livebridge::Json> pending_;
  // Feedback results from the telemetry worker, waiting to be answered on the platform thread.
  std::vector<std::pair<std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>, std::string>> replies_;
  // A kEventsMessage is on its way to the window and has not been answered yet.
  bool drain_requested_ = false;

  // A session is running; engine thread only. Its end triggers an upload of the statistics (when sharing is on).
  bool session_running_ = false;

  // Opt-in statistics and feedback. Before host_: the engine thread asks it to upload until host_ is joined; reset
  // right after host_ in the destructor, before the members its feedback callback uses.
  std::unique_ptr<WinTelemetry> telemetry_;

  // Last, and reset first in the destructor: its thread calls OnEngineEvent() until it is joined.
  std::unique_ptr<WinEngineHost> host_;
};

#endif  // RUNNER_LIVEBRIDGE_CHANNELS_H_
