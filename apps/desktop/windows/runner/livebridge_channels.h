#ifndef RUNNER_LIVEBRIDGE_CHANNELS_H_
#define RUNNER_LIVEBRIDGE_CHANNELS_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>

#include <memory>
#include <mutex>
#include <vector>

#include "livebridge/analytics_log.h"
#include "livebridge/json.h"

class WinEngineHost;

// The Windows side of docs/bridge-contract.md: the `livebridge/control` method channel and the
// `livebridge/events` event channel.
//
// This stage is "captions on Windows": devices, the microphone, the gateway connection, captions, level meters
// and the analytics log are real. Per-process capture, playback (and with it the test tone), the Save dialogs,
// telemetry, feedback and system language names are not ported yet; those methods answer without doing anything.
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

  // Hands the queued engine events to Flutter.
  void DrainEvents();

 private:
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // Engine thread: logs the event's numbers, then queues it for the platform thread.
  void OnEngineEvent(const livebridge::Json& event);

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
  // A kEventsMessage is on its way to the window and has not been answered yet.
  bool drain_requested_ = false;

  // Last, and reset first in the destructor: its thread calls OnEngineEvent() until it is joined.
  std::unique_ptr<WinEngineHost> host_;
};

#endif  // RUNNER_LIVEBRIDGE_CHANNELS_H_
