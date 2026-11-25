#include "livebridge_channels.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <cmath>
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <variant>

#include "audio_devices.h"
#include "livebridge/engine.h"
#include "settings_store.h"
#include "win_engine_host.h"
#include "win_util.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using livebridge::Engine;
using livebridge::Json;

// The local names stay clear of what <windows.h> defines: `small` is a macro there and `boolean` a type.
Json ToJson(const EncodableValue& value) {
  if (const auto* truth = std::get_if<bool>(&value)) return Json(*truth);
  if (const auto* narrow = std::get_if<std::int32_t>(&value)) return Json(static_cast<long long>(*narrow));
  if (const auto* wide = std::get_if<std::int64_t>(&value)) return Json(static_cast<long long>(*wide));
  if (const auto* number = std::get_if<double>(&value)) return Json(*number);
  if (const auto* text = std::get_if<std::string>(&value)) return Json(*text);
  if (const auto* list = std::get_if<EncodableList>(&value)) {
    Json::Array items;
    for (const EncodableValue& item : *list) items.push_back(ToJson(item));
    return Json(std::move(items));
  }
  if (const auto* map = std::get_if<EncodableMap>(&value)) {
    Json::Object members;
    for (const auto& [key, member] : *map) {
      if (const auto* name = std::get_if<std::string>(&key)) members.emplace_back(*name, ToJson(member));
    }
    return Json(std::move(members));
  }
  return Json();
}

EncodableValue FromJson(const Json& value) {
  if (value.is_bool()) return EncodableValue(value.as_bool());
  if (value.is_number()) {
    const double number = value.as_number();
    // Whole numbers go back as integers: Dart reads process ids and counts with `as int`.
    if (number == std::floor(number) && std::fabs(number) < 9.0e15) {
      return EncodableValue(static_cast<std::int64_t>(number));
    }
    return EncodableValue(number);
  }
  if (value.is_string()) return EncodableValue(value.as_string());
  if (value.is_array()) {
    EncodableList items;
    for (const Json& item : value.as_array()) items.push_back(FromJson(item));
    return EncodableValue(std::move(items));
  }
  if (value.is_object()) {
    EncodableMap members;
    for (const auto& [key, member] : value.as_object()) members[EncodableValue(key)] = FromJson(member);
    return EncodableValue(std::move(members));
  }
  return EncodableValue();
}

// The boolean argument `key` of a method call; false when it is missing.
bool Flag(const Json& arguments, std::string_view key) {
  const Json* value = arguments.find(key);
  return value != nullptr && value->as_bool();
}

// Control methods that take no arguments and map straight onto an engine command.
using Command = void (Engine::*)();
const std::map<std::string, Command> kCommands = {
    {"stop", &Engine::stop},
    {"pttDown", &Engine::ptt_down},
    {"pttUp", &Engine::ptt_up},
    {"panic", &Engine::panic},
};

// Methods whose work is not ported to Windows yet (playing a tone, the Save dialogs). They succeed, with no
// result, so the interface stays usable: for the two Save methods that reads as "the user cancelled".
const std::set<std::string> kNotOnWindowsYet = {"testTone", "saveTextFile", "analyticsExport"};

}  // namespace

LiveBridgeChannels::LiveBridgeChannels(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window), analytics_(AppDataFolder() / L"analytics.jsonl") {
  // `analyticsEnabled` is a saved preference; without one the log is on.
  const Json saved = settings_store::Load();
  const Json* analytics_enabled = saved.find("analyticsEnabled");
  analytics_.set_enabled(analytics_enabled == nullptr || analytics_enabled->as_bool(true));

  control_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "livebridge/control", &flutter::StandardMethodCodec::GetInstance());
  control_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  events_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger, "livebridge/events", &flutter::StandardMethodCodec::GetInstance());
  events_->SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
      [this](const EncodableValue* arguments, std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        sink_ = std::move(sink);
        return nullptr;
      },
      [this](const EncodableValue* arguments) -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        sink_.reset();
        return nullptr;
      }));

  // Started last: from here on OnEngineEvent() may be called, on the engine thread.
  host_ = std::make_unique<WinEngineHost>([this](const Json& event) { OnEngineEvent(event); });
}

LiveBridgeChannels::~LiveBridgeChannels() {
  // Joins the engine thread, which closes a running session on its way out. After this nothing calls
  // OnEngineEvent() any more, and the members it uses can go.
  host_.reset();
  control_->SetMethodCallHandler(nullptr);
  events_->SetStreamHandler(nullptr);
}

void LiveBridgeChannels::OnEngineEvent(const Json& event) {
  // The log keeps numbers only; it ignores the events it has no use for (meters, devicesChanged). It writes to
  // disk, which is why this happens here, on the engine thread, and never on an audio thread.
  analytics_.record(event);

  bool ask_for_drain = false;
  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    pending_.push_back(event);
    ask_for_drain = !drain_requested_;
    drain_requested_ = true;
  }
  // One message per batch. If it cannot be posted (the window is going away), the next event tries again.
  if (ask_for_drain && !::PostMessageW(window_, kEventsMessage, 0, 0)) {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    drain_requested_ = false;
  }
}

void LiveBridgeChannels::DrainEvents() {
  std::vector<Json> events;
  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    events.swap(pending_);
    drain_requested_ = false;
  }
  // Nobody listening (the interface has not subscribed yet, or has left): the events are dropped.
  if (!sink_) return;
  for (const Json& event : events) sink_->Success(FromJson(event));
}

void LiveBridgeChannels::HandleMethodCall(const flutter::MethodCall<EncodableValue>& call,
                                          std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const Json arguments = call.arguments() ? ToJson(*call.arguments()) : Json();

  if (method == "listDevices") {
    result->Success(FromJson(audio_devices::ListForBridge()));
  } else if (method == "listAudioProcesses") {
    // Capturing one app's audio is not ported yet, so there is nothing to choose from.
    result->Success(EncodableValue(EncodableList{}));
  } else if (method == "loadSettings") {
    result->Success(FromJson(settings_store::Load()));
  } else if (method == "saveSettings") {
    const Json* analytics_enabled = arguments.find("analyticsEnabled");
    if (analytics_enabled != nullptr && analytics_enabled->is_bool()) {
      analytics_.set_enabled(analytics_enabled->as_bool());
    }
    if (call.arguments()) settings_store::Save(arguments);
    result->Success();
  } else if (method == "start") {
    // Waits for the engine thread's verdict on the settings; what the session then does arrives as events.
    const bool valid = host_->Call([&arguments](Engine& engine) { return engine.start(arguments); });
    if (valid) {
      result->Success();
    } else {
      result->Error("invalid_settings", "The session settings are missing or invalid.");
    }
  } else if (kCommands.count(method) > 0) {
    const Command command = kCommands.at(method);
    host_->Post([command](Engine& engine) { (engine.*command)(); });
    result->Success();
  } else if (method == "setOutgoingMuted") {
    const bool muted = Flag(arguments, "muted");
    host_->Post([muted](Engine& engine) { engine.set_outgoing_muted(muted); });
    result->Success();
  } else if (method == "setIncomingAudioMuted") {
    const bool muted = Flag(arguments, "muted");
    host_->Post([muted](Engine& engine) { engine.set_incoming_audio_muted(muted); });
    result->Success();
  } else if (method == "setBypass") {
    const bool enabled = Flag(arguments, "enabled");
    host_->Post([enabled](Engine& engine) { engine.set_bypass(enabled); });
    result->Success();
  } else if (method == "startMeters") {
    // `sourcePids` has no use yet: there is no per-process capture to meter.
    const Json* microphone = arguments.find("micUid");
    host_->StartMeters(microphone != nullptr ? microphone->as_string() : std::string());
    result->Success();
  } else if (method == "stopMeters") {
    host_->StopMeters();
    result->Success();
  } else if (method == "microphonePermission") {
    // Windows asks nothing of a desktop app here. (The privacy switch that blocks microphones for desktop apps
    // shows up as silence or as a failure to open the device.)
    result->Success(EncodableValue("granted"));
  } else if (method == "requestMicrophonePermission") {
    result->Success(EncodableValue(true));
  } else if (method == "rateTurn") {
    const Json* direction = arguments.find("direction");
    const Json* turn = arguments.find("turnId");
    const Json* rating = arguments.find("rating");
    if (direction != nullptr && direction->is_string() && turn != nullptr && turn->is_number() &&
        rating != nullptr && rating->is_string()) {
      analytics_.rate(direction->as_string(), turn->as_int(), rating->as_string());
      result->Success();
    } else {
      result->Error("bad_arguments", "missing or invalid arguments");
    }
  } else if (method == "analyticsSummary") {
    result->Success(FromJson(analytics_.summary()));
  } else if (method == "analyticsClear") {
    analytics_.clear();
    result->Success();
  } else if (method == "languageNames") {
    // No names from the system yet: the app falls back to its own and to the English ones.
    result->Success(EncodableValue(EncodableMap{}));
  } else if (method == "telemetryStatus") {
    result->Success(EncodableValue(EncodableMap{{EncodableValue("enabled"), EncodableValue(false)}}));
  } else if (method == "sendFeedback") {
    result->Error("feedback_failed", "Feedback cannot be sent from the Windows build yet.");
  } else if (kNotOnWindowsYet.count(method) > 0) {
    result->Success();
  } else {
    result->NotImplemented();
  }
}
