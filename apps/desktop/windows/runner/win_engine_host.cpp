#include "win_engine_host.h"

#include <windows.h>

#include <objbase.h>

#include <chrono>
#include <utility>

#include "audio_devices.h"
#include "gateway_socket.h"
#include "wasapi_capture.h"

namespace {

using livebridge::Direction;
using livebridge::Engine;
using livebridge::HostError;
using livebridge::Json;

// The longest the engine waits for its next tick().
const std::chrono::milliseconds kTick(20);
const std::uint64_t kMetersEveryUs = 100'000;
const double kSilenceDb = -120.0;

}  // namespace

WinEngineHost::WinEngineHost(EventCallback on_event)
    : on_event_(std::move(on_event)), devices_changed_(std::make_shared<std::atomic<bool>>(false)) {
  LARGE_INTEGER frequency = {};
  if (::QueryPerformanceFrequency(&frequency) && frequency.QuadPart > 0) {
    ticks_per_second_ = static_cast<std::uint64_t>(frequency.QuadPart);
  }
  thread_ = std::thread([this] { Run(); });
}

WinEngineHost::~WinEngineHost() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    quit_ = true;
  }
  wake_.notify_all();
  if (thread_.joinable()) thread_.join();
}

void WinEngineHost::Post(Task task) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    tasks_.push_back(std::move(task));
  }
  wake_.notify_all();
}

bool WinEngineHost::Call(const std::function<bool(livebridge::Engine&)>& question) {
  std::mutex answer_mutex;
  std::condition_variable answered;
  bool done = false;
  bool answer = false;
  Post([&](Engine& engine) {
    const bool value = question(engine);
    // Notified under the lock: the caller cannot wake, return and destroy `answered` before this is through.
    std::lock_guard<std::mutex> guard(answer_mutex);
    answer = value;
    done = true;
    answered.notify_all();
  });
  std::unique_lock<std::mutex> lock(answer_mutex);
  answered.wait(lock, [&done] { return done; });
  return answer;
}

void WinEngineHost::StartMeters(std::string mic_uid) {
  Post([this, uid = std::move(mic_uid)](Engine&) {
    meter_microphone_.reset();
    // A running session reports its own microphone already.
    if (microphone_) return;
    meters_on_ = true;
    livebridge::DeviceInfo info;
    if (uid.empty() || !audio_devices::Find(uid, info) || info.input_channels <= 0) return;
    auto capture = std::make_unique<WasapiCapture>();
    HostError error;
    if (capture->Start(uid, nullptr, error)) {
      meter_microphone_ = std::move(capture);
    } else {
      on_event_(Json(Json::Object{
          {"type", "error"}, {"code", error.code}, {"message", error.message}, {"fatal", false}}));
    }
  });
}

void WinEngineHost::StopMeters() {
  Post([this](Engine&) {
    meter_microphone_.reset();
    if (!microphone_) meters_on_ = false;
  });
}

// The engine thread.

void WinEngineHost::Run() {
  const HRESULT com = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    // In this scope, so that everything that uses COM is gone before COM is.
    audio_devices::ChangeWatcher watcher(devices_changed_);
    Engine engine(*this, on_event_);
    std::vector<Task> batch;
    for (;;) {
      {
        std::unique_lock<std::mutex> lock(mutex_);
        wake_.wait_for(lock, kTick, [this] { return quit_ || !tasks_.empty(); });
        if (quit_) break;
        batch.swap(tasks_);
      }
      for (const Task& task : batch) task(engine);
      batch.clear();
      // One call however many notifications arrived: the engine tells the interface and checks its own devices.
      if (devices_changed_->exchange(false)) engine.on_devices_changed();
      engine.tick();
      EmitMeters();
    }
    // Quitting: a running session is closed (its connection, its microphone), not abandoned.
    engine.panic();
    meter_microphone_.reset();
  }
  if (SUCCEEDED(com)) ::CoUninitialize();
}

void WinEngineHost::EmitMeters() {
  if (!meters_on_) return;
  const std::uint64_t now = now_us();
  if (now < next_meters_us_) return;
  next_meters_us_ = now + kMetersEveryUs;
  const WasapiCapture* capture = microphone_ ? microphone_.get() : meter_microphone_.get();
  const double level = capture != nullptr ? capture->level_db() : kSilenceDb;
  // No meeting source and no playback queues in this stage: those three report "nothing".
  on_event_(Json(Json::Object{
      {"type", "meters"}, {"mic", level}, {"source", kSilenceDb}, {"outQueueMs", 0.0}, {"inQueueMs", 0.0}}));
}

// livebridge::EngineHost: called by the engine, on the engine thread.

std::uint64_t WinEngineHost::now_us() {
  LARGE_INTEGER ticks = {};
  if (ticks_per_second_ == 0 || !::QueryPerformanceCounter(&ticks)) return ::GetTickCount64() * 1000;
  const std::uint64_t count = static_cast<std::uint64_t>(ticks.QuadPart);
  // Whole seconds and the remainder separately, so that the multiplication cannot overflow.
  return (count / ticks_per_second_) * 1'000'000 + ((count % ticks_per_second_) * 1'000'000) / ticks_per_second_;
}

void WinEngineHost::connect(const std::string& gateway_url, const std::string& access_token) {
  const std::uint64_t id = ++last_connection_id_;
  connection_id_ = id;
  // The socket calls these on its own threads; each only posts, and the posted task checks that the connection it
  // came from is still the current one.
  GatewaySocket::Events events;
  events.opened = [this, id] {
    Post([this, id](Engine& engine) {
      if (id == connection_id_) engine.on_transport_open();
    });
  };
  events.message = [this, id](bool binary, std::string payload) {
    Post([this, id, binary, bytes = std::move(payload)](Engine& engine) {
      if (id != connection_id_) return;
      if (binary) {
        engine.on_transport_binary(reinterpret_cast<const std::uint8_t*>(bytes.data()), bytes.size());
      } else {
        engine.on_transport_text(bytes);
      }
    });
  };
  events.closed = [this, id](std::string code, std::string reason) {
    Post([this, id, why = std::move(code), detail = std::move(reason)](Engine& engine) {
      if (id == connection_id_) engine.on_transport_closed(why, detail);
    });
  };
  socket_ = std::make_unique<GatewaySocket>(gateway_url, access_token, std::move(events));
}

void WinEngineHost::send_text(const std::string& json) {
  if (socket_) socket_->SendText(json);
}

bool WinEngineHost::send_binary(const std::uint8_t* data, std::size_t size) {
  return socket_ && socket_->SendBinary(data, size);
}

void WinEngineHost::close() {
  // From here on, whatever this connection has queued for the engine thread finds another id and does nothing.
  connection_id_ = 0;
  // Joins the socket's threads. They may be posting at this moment; that needs the queue's lock only, which the
  // engine thread does not hold while it runs a task or a tick.
  socket_.reset();
}

bool WinEngineHost::find_device(const std::string& uid, livebridge::DeviceInfo& info) {
  return audio_devices::Find(uid, info);
}

bool WinEngineHost::open_microphone(const std::string& device_uid, HostError& error) {
  // From here on the session's own capture feeds the level meter.
  meter_microphone_.reset();
  const std::uint64_t id = ++last_microphone_id_;
  auto capture = std::make_unique<WasapiCapture>();
  const bool opened = capture->Start(
      device_uid,
      [this, id](const std::uint8_t* pcm, std::size_t bytes) {
        // On the capture thread: copy the block and leave.
        Post([this, id, block = std::vector<std::uint8_t>(pcm, pcm + bytes)](Engine& engine) {
          if (id == microphone_id_) engine.on_captured(Direction::out, block.data(), block.size());
        });
      },
      error);
  if (!opened) return false;
  microphone_ = std::move(capture);
  microphone_id_ = id;
  meters_on_ = true;
  return true;
}

void WinEngineHost::close_microphone() {
  microphone_id_ = 0;
  microphone_.reset();
  // The meters ran for the session. The setup screen asks again when it wants them.
  meters_on_ = false;
}

bool WinEngineHost::open_source(const std::vector<int>&, HostError& error) {
  error = {"unsupported",
           "Capturing the meeting app's audio is not part of this Windows build yet; it arrives in a later one."};
  return false;
}

void WinEngineHost::close_source() {}

bool WinEngineHost::source_alive() { return true; }

bool WinEngineHost::open_sink(Direction, const std::string&, HostError& error) {
  error = {"unsupported",
           "Playing translated speech is not part of this Windows build yet; it arrives in a later one. "
           "Use the captions mode."};
  return false;
}

void WinEngineHost::close_sink(Direction) {}

bool WinEngineHost::sink_write(Direction, const std::uint8_t*, std::size_t, int) { return false; }

void WinEngineHost::sink_end_input(Direction) {}

void WinEngineHost::sink_flush(Direction) {}

void WinEngineHost::sink_set_muted(Direction, bool) {}

std::int64_t WinEngineHost::sink_written(Direction) { return 0; }

std::int64_t WinEngineHost::sink_consumed(Direction) { return 0; }
