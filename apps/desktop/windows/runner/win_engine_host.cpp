#include "win_engine_host.h"

#include <windows.h>

#include <objbase.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <utility>

#include "audio_devices.h"
#include "gateway_socket.h"
#include "livebridge/audio_dsp.h"
#include "livebridge/source_mixer.h"
#include "wasapi_capture.h"
#include "wasapi_loopback.h"
#include "wasapi_sink.h"

namespace {

using livebridge::Direction;
using livebridge::Engine;
using livebridge::HostError;
using livebridge::Json;

// The longest the engine waits for its next tick().
const std::chrono::milliseconds kTick(20);
const std::uint64_t kMetersEveryUs = 100'000;
const double kSilenceDb = -120.0;
// The meeting source's mixer: each process may queue 2 s, and may run 200 ms ahead of a silent or stalled one
// (16 kHz samples).
const std::size_t kSourceQueueSamples = static_cast<std::size_t>(WasapiLoopback::kSampleRate) * 2;
const std::size_t kSourceMaxLagSamples = static_cast<std::size_t>(WasapiLoopback::kSampleRate) / 5;
// The test tone: 0.6 s of 440 Hz at -18 dBFS, its sink closed 1 s after it was opened.
const int kToneMs = 600;
const double kToneHz = 440.0;
const double kToneDb = -18.0;
const std::uint64_t kToneLifetimeUs = 1'000'000;
const double kPi = 3.14159265358979323846;

// out = 0, in = 1: the values of the enum (frame_codec.h).
std::size_t Slot(Direction direction) { return static_cast<std::size_t>(direction); }

// The test tone as PCM s16 at the sinks' own rate, so that it plays without resampling.
std::vector<std::int16_t> ToneSamples() {
  const std::size_t total = static_cast<std::size_t>(WasapiSink::kSampleRate) * kToneMs / 1000;
  const double amplitude = std::pow(10.0, kToneDb / 20.0) * 32767.0;
  std::vector<std::int16_t> samples(total);
  for (std::size_t i = 0; i < total; i++) {
    const double phase = 2.0 * kPi * kToneHz * static_cast<double>(i) / WasapiSink::kSampleRate;
    samples[i] = static_cast<std::int16_t>(std::lround(amplitude * std::sin(phase)));
  }
  return samples;
}

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

void WinEngineHost::StartMeters(std::string mic_uid, std::vector<int> source_pids) {
  Post([this, uid = std::move(mic_uid), pids = std::move(source_pids)](Engine&) {
    meter_microphone_.reset();
    meter_loopbacks_.clear();
    // A running session reports its own captures already.
    if (microphone_) return;
    meters_on_ = true;
    HostError error;
    livebridge::DeviceInfo info;
    if (!uid.empty() && audio_devices::Find(uid, info) && info.input_channels > 0) {
      auto capture = std::make_unique<WasapiCapture>();
      if (capture->Start(uid, nullptr, error)) {
        meter_microphone_ = std::move(capture);
      } else {
        EmitError(error);
      }
    }
    for (const int pid : pids) {
      auto loopback = std::make_unique<WasapiLoopback>();
      if (!loopback->Start(pid, nullptr, error)) {
        // One error is enough: the others would most likely say the same.
        EmitError(error);
        break;
      }
      meter_loopbacks_.push_back(std::move(loopback));
    }
  });
}

void WinEngineHost::StopMeters() {
  Post([this](Engine&) {
    meter_microphone_.reset();
    meter_loopbacks_.clear();
    if (!microphone_) meters_on_ = false;
  });
}

void WinEngineHost::TestTone(std::string device_uid) {
  Post([this, uid = std::move(device_uid)](Engine&) {
    HostError error = {"device", "cannot open that output device"};
    livebridge::DeviceInfo info;
    auto sink = std::make_unique<WasapiSink>();
    if (!audio_devices::Find(uid, info) || info.output_channels <= 0 || !sink->Open(uid, error)) {
      EmitError(error);
      return;
    }
    // One quiet tone per test: queued whole and ended at once, so it plays without waiting to prebuffer.
    const std::vector<std::int16_t> tone = ToneSamples();
    sink->Write(reinterpret_cast<const std::uint8_t*>(tone.data()), tone.size() * sizeof(std::int16_t),
                WasapiSink::kSampleRate);
    sink->EndInput();
    tones_.push_back(Tone{std::move(sink), now_us() + kToneLifetimeUs});
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
      PumpSource(engine);
      engine.tick();
      CloseFinishedTones();
      EmitMeters();
    }
    // Quitting: a running session is closed (its connection, its captures, its sinks), not abandoned.
    engine.panic();
    meter_microphone_.reset();
    meter_loopbacks_.clear();
    tones_.clear();
  }
  if (SUCCEEDED(com)) ::CoUninitialize();
}

void WinEngineHost::PumpSource(Engine& engine) {
  if (!source_mixer_) return;
  source_mixed_.clear();
  if (source_mixer_->mix(source_mixed_) == 0) return;
  source_pcm_.resize(source_mixed_.size());
  livebridge::float_to_int16(source_mixed_.data(), source_mixed_.size(), source_pcm_.data());
  // Last: the engine may close the source from in here, and nothing of it is touched afterwards.
  engine.on_captured(Direction::in, reinterpret_cast<const std::uint8_t*>(source_pcm_.data()),
                     source_pcm_.size() * sizeof(std::int16_t));
}

void WinEngineHost::CloseFinishedTones() {
  if (tones_.empty()) return;
  const std::uint64_t now = now_us();
  const auto finished = [now](const Tone& tone) { return now >= tone.close_at_us; };
  // Destroying a sink joins its render thread, which wakes every few milliseconds.
  tones_.erase(std::remove_if(tones_.begin(), tones_.end(), finished), tones_.end());
}

void WinEngineHost::EmitMeters() {
  if (!meters_on_) return;
  const std::uint64_t now = now_us();
  if (now < next_meters_us_) return;
  next_meters_us_ = now + kMetersEveryUs;
  const WasapiCapture* capture = microphone_ ? microphone_.get() : meter_microphone_.get();
  const double mic = capture != nullptr ? capture->level_db() : kSilenceDb;
  // The session's meeting source when it has one, the setup screen's otherwise: the loudest of its processes.
  const std::vector<std::unique_ptr<WasapiLoopback>>& loopbacks =
      source_loopbacks_.empty() ? meter_loopbacks_ : source_loopbacks_;
  double source = kSilenceDb;
  for (const auto& loopback : loopbacks) source = std::max(source, loopback->level_db());
  const double out_queue_ms = sinks_[0] ? sinks_[0]->queued_ms() : 0.0;
  const double in_queue_ms = sinks_[1] ? sinks_[1]->queued_ms() : 0.0;
  on_event_(Json(Json::Object{{"type", "meters"},
                              {"mic", mic},
                              {"source", source},
                              {"outQueueMs", out_queue_ms},
                              {"inQueueMs", in_queue_ms}}));
}

void WinEngineHost::EmitError(const HostError& error) {
  on_event_(Json(Json::Object{{"type", "error"}, {"code", error.code}, {"message", error.message}, {"fatal", false}}));
}

WasapiSink* WinEngineHost::Sink(Direction direction) { return sinks_[Slot(direction)].get(); }

// livebridge::EngineHost: called by the engine, on the engine thread.

std::uint64_t WinEngineHost::now_us() {
  LARGE_INTEGER ticks = {};
  if (ticks_per_second_ == 0 || !::QueryPerformanceCounter(&ticks)) return ::GetTickCount64() * 1000;
  const std::uint64_t count = static_cast<std::uint64_t>(ticks.QuadPart);
  // Whole seconds and the remainder separately, so that the multiplication cannot overflow.
  return (count / ticks_per_second_) * 1'000'000 + ((count % ticks_per_second_) * 1'000'000) / ticks_per_second_;
}

void WinEngineHost::connect(const std::string& gateway_url, const livebridge::SessionRequest& request) {
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
  socket_ = std::make_unique<GatewaySocket>(gateway_url, request, std::move(events));
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
  // From here on the session's own captures feed the level meters.
  meter_microphone_.reset();
  meter_loopbacks_.clear();
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

bool WinEngineHost::open_source(const std::vector<int>& process_ids, HostError& error) {
  close_source();
  if (process_ids.empty()) {
    error = {"source_gone", "No meeting app was chosen; pick it again."};
    return false;
  }
  // The setup screen's meters would capture the same processes a second time.
  meter_loopbacks_.clear();
  auto mixer = std::make_unique<livebridge::SourceMixer>(process_ids.size(), kSourceQueueSamples, kSourceMaxLagSamples);
  std::vector<std::unique_ptr<WasapiLoopback>> loopbacks;
  for (std::size_t input = 0; input < process_ids.size(); input++) {
    livebridge::SourceMixer* target = mixer.get();
    // Called on the loopback's thread, the only producer of this input: no lock, no Post().
    WasapiLoopback::AudioCallback deliver = [target, input](const float* samples, std::size_t sample_count) {
      target->push(input, samples, sample_count);
    };
    auto loopback = std::make_unique<WasapiLoopback>();
    if (!loopback->Start(process_ids[input], std::move(deliver), error)) {
      // The ones already running stop before the mixer they feed goes.
      loopbacks.clear();
      return false;
    }
    loopbacks.push_back(std::move(loopback));
  }
  source_mixer_ = std::move(mixer);
  source_loopbacks_ = std::move(loopbacks);
  return true;
}

void WinEngineHost::close_source() {
  // The loopbacks first: their threads push into the mixer until they are joined.
  source_loopbacks_.clear();
  source_mixer_.reset();
}

bool WinEngineHost::source_alive() {
  for (const auto& loopback : source_loopbacks_) {
    if (!loopback->ProcessRunning()) return false;
  }
  return true;
}

bool WinEngineHost::open_sink(Direction direction, const std::string& device_uid, HostError& error) {
  std::unique_ptr<WasapiSink>& slot = sinks_[Slot(direction)];
  slot.reset();
  auto sink = std::make_unique<WasapiSink>();
  if (!sink->Open(device_uid, error)) return false;
  slot = std::move(sink);
  return true;
}

void WinEngineHost::close_sink(Direction direction) { sinks_[Slot(direction)].reset(); }

bool WinEngineHost::sink_write(Direction direction, const std::uint8_t* pcm, std::size_t bytes, int sample_rate) {
  WasapiSink* sink = Sink(direction);
  return sink != nullptr && sink->Write(pcm, bytes, sample_rate);
}

void WinEngineHost::sink_end_input(Direction direction) {
  WasapiSink* sink = Sink(direction);
  if (sink != nullptr) sink->EndInput();
}

void WinEngineHost::sink_flush(Direction direction) {
  WasapiSink* sink = Sink(direction);
  if (sink != nullptr) sink->Flush();
}

void WinEngineHost::sink_set_muted(Direction direction, bool muted) {
  WasapiSink* sink = Sink(direction);
  if (sink != nullptr) sink->SetMuted(muted);
}

std::int64_t WinEngineHost::sink_written(Direction direction) {
  const WasapiSink* sink = Sink(direction);
  return sink != nullptr ? sink->written() : 0;
}

std::int64_t WinEngineHost::sink_consumed(Direction direction) {
  const WasapiSink* sink = Sink(direction);
  return sink != nullptr ? sink->consumed() : 0;
}
