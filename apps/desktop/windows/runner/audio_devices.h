#ifndef RUNNER_AUDIO_DEVICES_H_
#define RUNNER_AUDIO_DEVICES_H_

#include <atomic>
#include <memory>
#include <string>

#include "livebridge/engine.h"
#include "livebridge/json.h"

struct IMMDeviceEnumerator;
struct IMMNotificationClient;

// The audio endpoints of this PC, from WASAPI's device list (the MMDevice API). A device's uid is its endpoint id.
//
// COM must be initialised on the calling thread. Either kind of apartment will do: the platform thread is a
// single-threaded apartment, the engine thread is in the multithreaded one.
namespace audio_devices {

// The `listDevices` result of docs/bridge-contract.md: one map per active endpoint. A capture endpoint has
// `inputChannels`, a render endpoint `outputChannels`; the other count is 0.
livebridge::Json ListForBridge();

// What the engine needs to know about one active endpoint. False when there is no active endpoint with this uid.
bool Find(const std::string& uid, livebridge::DeviceInfo& info);

// While it lives, sets `*changed` each time an endpoint is added, removed, enabled or disabled, or another endpoint
// becomes the default. The system calls from threads of its own, so the flag is all that is touched there: the owner
// polls and clears it. Create and destroy it on the same thread, with COM initialised.
class ChangeWatcher {
 public:
  explicit ChangeWatcher(std::shared_ptr<std::atomic<bool>> changed);
  ~ChangeWatcher();
  ChangeWatcher(const ChangeWatcher&) = delete;
  ChangeWatcher& operator=(const ChangeWatcher&) = delete;

 private:
  // Both null when the notifications could not be set up; the app then works without them.
  IMMDeviceEnumerator* enumerator_ = nullptr;
  IMMNotificationClient* client_ = nullptr;
};

}  // namespace audio_devices

#endif  // RUNNER_AUDIO_DEVICES_H_
