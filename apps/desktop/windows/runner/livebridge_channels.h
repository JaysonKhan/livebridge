#ifndef RUNNER_LIVEBRIDGE_CHANNELS_H_
#define RUNNER_LIVEBRIDGE_CHANNELS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>

#include <memory>

// The Windows side of docs/bridge-contract.md: the `livebridge/control` method channel and the
// `livebridge/events` event channel.
//
// Today this is the shell only: settings are saved and loaded, and every audio method answers without doing
// anything — `start` says so with an error. The audio engine (WASAPI capture and playback, the gateway
// connection) is not ported yet.
class LiveBridgeChannels {
 public:
  explicit LiveBridgeChannels(flutter::BinaryMessenger* messenger);
  ~LiveBridgeChannels();

 private:
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> control_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  // Where engine events will be sent once there is an engine.
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
};

#endif  // RUNNER_LIVEBRIDGE_CHANNELS_H_
