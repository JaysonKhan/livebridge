#ifndef RUNNER_WIN_ENGINE_HOST_H_
#define RUNNER_WIN_ENGINE_HOST_H_

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "livebridge/engine.h"
#include "livebridge/json.h"

class GatewaySocket;
class WasapiCapture;

// The Windows platform layer of the audio engine: the engine thread, and everything the portable session logic
// (livebridge::Engine) asks of the platform through livebridge::EngineHost.
//
// Who runs what:
//   Platform (UI) thread  Flutter's method calls. Creates and destroys the host and calls only Post(), Call(),
//                         StartMeters() and StopMeters(). It never touches the engine.
//   Engine thread         Owned by this class; COM multithreaded apartment. Runs the posted tasks, Engine::tick()
//                         (every 20 ms, or sooner when a task arrives), the meters timer, every Engine method, every
//                         EngineHost method below (the engine calls those from inside its own methods) and the event
//                         callback. Creates and destroys the gateway socket and the captures.
//   Socket threads        Two per gateway connection (gateway_socket.h). Their callbacks only Post().
//   Capture thread        One per open microphone (wasapi_capture.h). Its callback only Post()s the PCM; the level
//                         is read through an atomic.
//   System threads        Device-change notifications. They only raise an atomic flag that the engine thread polls.
//
// So no Engine method is ever called off the engine thread, and no EngineHost method calls back into the engine:
// whatever a host method starts reports back as a task posted to the engine thread. A task posted by a connection
// or by a capture carries its id and does nothing once that connection or capture has been closed.
//
// This stage is "captions on Windows": the gateway connection, the device list and the microphone are real;
// per-process capture and the playback sinks are not there yet and say so.
class WinEngineHost final : public livebridge::EngineHost {
 public:
  using Task = std::function<void(livebridge::Engine&)>;
  using EventCallback = std::function<void(const livebridge::Json&)>;

  // `on_event` gets every engine event, and the `meters` events made here, on the engine thread. It must return
  // quickly and must not wait for this object.
  explicit WinEngineHost(EventCallback on_event);
  // Stops a running session and joins the engine thread: `on_event` is not called after this returns.
  ~WinEngineHost() override;
  WinEngineHost(const WinEngineHost&) = delete;
  WinEngineHost& operator=(const WinEngineHost&) = delete;

  // Runs `task` on the engine thread, soon. Callable from any thread.
  void Post(Task task);
  // Runs `question` on the engine thread and waits for its answer. Not from the engine thread itself.
  bool Call(const std::function<bool(livebridge::Engine&)>& question);

  // The setup screen's level meter: `meters` events about ten times a second until StopMeters(), with the level of
  // this microphone (an empty uid: no microphone, the events report silence). While a session runs the events come
  // anyway, from the session's own capture, and these two change nothing.
  void StartMeters(std::string mic_uid);
  void StopMeters();

 private:
  // livebridge::EngineHost. Called by the engine, on the engine thread.
  std::uint64_t now_us() override;
  void connect(const std::string& gateway_url, const std::string& access_token) override;
  void send_text(const std::string& json) override;
  bool send_binary(const std::uint8_t* data, std::size_t size) override;
  void close() override;
  bool find_device(const std::string& uid, livebridge::DeviceInfo& info) override;
  bool open_microphone(const std::string& device_uid, livebridge::HostError& error) override;
  void close_microphone() override;
  bool open_source(const std::vector<int>& process_ids, livebridge::HostError& error) override;
  void close_source() override;
  bool source_alive() override;
  bool open_sink(livebridge::Direction direction, const std::string& device_uid, livebridge::HostError& error) override;
  void close_sink(livebridge::Direction direction) override;
  bool sink_write(livebridge::Direction direction, const std::uint8_t* pcm, std::size_t bytes,
                  int sample_rate) override;
  void sink_end_input(livebridge::Direction direction) override;
  void sink_flush(livebridge::Direction direction) override;
  void sink_set_muted(livebridge::Direction direction, bool muted) override;
  std::int64_t sink_written(livebridge::Direction direction) override;
  std::int64_t sink_consumed(livebridge::Direction direction) override;

  // The engine thread.
  void Run();
  void EmitMeters();

  const EventCallback on_event_;
  // Ticks of the performance counter per second; 0 when the system has none.
  std::uint64_t ticks_per_second_ = 0;
  // Raised by the system when the set of audio devices changed; taken down by the engine thread.
  const std::shared_ptr<std::atomic<bool>> devices_changed_;

  // The task queue: the only state shared with other threads.
  std::mutex mutex_;
  std::condition_variable wake_;
  std::vector<Task> tasks_;
  bool quit_ = false;

  // Engine thread only, from here down.
  std::unique_ptr<GatewaySocket> socket_;
  // The id of the connection in `socket_`, 0 when there is none; and the last id handed out.
  std::uint64_t connection_id_ = 0;
  std::uint64_t last_connection_id_ = 0;
  // The session's microphone, with an id of the same kind.
  std::unique_ptr<WasapiCapture> microphone_;
  std::uint64_t microphone_id_ = 0;
  std::uint64_t last_microphone_id_ = 0;
  // The setup screen's microphone: it feeds the level meter and nothing else.
  std::unique_ptr<WasapiCapture> meter_microphone_;
  bool meters_on_ = false;
  std::uint64_t next_meters_us_ = 0;

  std::thread thread_;
};

#endif  // RUNNER_WIN_ENGINE_HOST_H_
