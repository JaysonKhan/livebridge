#include "livebridge_channels.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <cmath>
#include <cstdint>
#include <cwchar>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

#include "audio_devices.h"
#include "audio_processes.h"
#include "file_dialogs.h"
#include "livebridge/engine.h"
#include "livebridge/telemetry_uploader.h"
#include "settings_store.h"
#include "utils.h"
#include "win_engine_host.h"
#include "win_telemetry.h"
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

}  // namespace

LiveBridgeChannels::LiveBridgeChannels(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window), analytics_(AppDataFolder() / L"analytics.jsonl") {
  // `analyticsEnabled` is a saved preference; without one the log is on.
  const Json saved = settings_store::Load();
  const Json* analytics_enabled = saved.find("analyticsEnabled");
  analytics_.set_enabled(analytics_enabled == nullptr || analytics_enabled->as_bool(true));

  // Statistics (numbers only): on unless the user switched sharing off; a saved `false` stays off. Uploads what is
  // pending at start.
  const Json* endpoint = saved.find("telemetryEndpoint");
  telemetry_ = std::make_unique<WinTelemetry>(analytics_.path(), FLUTTER_VERSION,
                                              endpoint != nullptr ? endpoint->as_string() : std::string());
  if (const Json* language = saved.find("uiLanguage")) telemetry_->SetUiLanguage(language->as_string());
  const Json* sharing = saved.find("telemetryEnabled");
  telemetry_->SetEnabled(sharing == nullptr || sharing->as_bool(true));
  telemetry_->UploadPending();

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
  // Joins the telemetry worker: after this no feedback callback touches replies_.
  telemetry_.reset();
  control_->SetMethodCallHandler(nullptr);
  events_->SetStreamHandler(nullptr);
}

void LiveBridgeChannels::OnEngineEvent(const Json& event) {
  // The log keeps numbers only; it ignores the events it has no use for (meters, devicesChanged). It writes to
  // disk, which is why this happens here, on the engine thread, and never on an audio thread.
  analytics_.record(event);

  // When a session ends its records are on disk now: upload them (a no-op unless sharing is on).
  const Json* type = event.find("type");
  const Json* phase = event.find("state");
  if (type != nullptr && type->as_string() == "state" && phase != nullptr && phase->is_string()) {
    const bool running = phase->as_string() != "idle";
    if (session_running_ && !running) telemetry_->UploadPending();
    session_running_ = running;
  }

  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    pending_.push_back(event);
  }
  RequestDrain();
}

void LiveBridgeChannels::RequestDrain() {
  bool ask_for_drain = false;
  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    ask_for_drain = !drain_requested_;
    drain_requested_ = true;
  }
  // One message per batch. If it cannot be posted (the window is going away), the next request tries again.
  if (ask_for_drain && !::PostMessageW(window_, kEventsMessage, 0, 0)) {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    drain_requested_ = false;
  }
}

void LiveBridgeChannels::DrainEvents() {
  std::vector<Json> events;
  std::vector<std::pair<std::shared_ptr<flutter::MethodResult<EncodableValue>>, std::string>> replies;
  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    events.swap(pending_);
    replies.swap(replies_);
    drain_requested_ = false;
  }
  for (auto& [reply, code] : replies) {
    if (code.empty()) {
      reply->Success();
    } else {
      reply->Error(code, "The feedback was not sent.");
    }
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
    result->Success(FromJson(audio_processes::ListForBridge()));
  } else if (method == "loadSettings") {
    result->Success(FromJson(settings_store::Load()));
  } else if (method == "saveSettings") {
    const Json* analytics_enabled = arguments.find("analyticsEnabled");
    if (analytics_enabled != nullptr && analytics_enabled->is_bool()) {
      analytics_.set_enabled(analytics_enabled->as_bool());
    }
    const Json* language = arguments.find("uiLanguage");
    if (language != nullptr && language->is_string()) telemetry_->SetUiLanguage(language->as_string());
    const Json* sharing = arguments.find("telemetryEnabled");
    if (sharing != nullptr && sharing->is_bool()) {
      telemetry_->SetEnabled(sharing->as_bool());
      telemetry_->UploadPending();
    }
    const std::vector<std::string> failed =
        call.arguments() ? settings_store::Save(arguments) : std::vector<std::string>();
    if (failed.empty()) {
      result->Success();
    } else {
      // Only the keys of the secrets that could not be stored are named, never their values.
      std::string keys;
      for (const std::string& key : failed) {
        if (!keys.empty()) keys += ", ";
        keys += key;
      }
      result->Error("settings_failed", "could not store: " + keys);
    }
  } else if (method == "start") {
    // Waits for the engine thread's verdict on the settings; what the session then does arrives as events.
    const bool valid = host_->Call([&arguments](Engine& engine) { return engine.start(arguments); });
    if (valid) {
      result->Success();
    } else {
      result->Error("invalid_settings", "The session settings are missing or invalid.");
    }
  } else if (method == "updateAccessToken") {
    const Json* token = arguments.find("accessToken");
    if (token != nullptr && token->is_string() && !token->as_string().empty()) {
      // The running session's next reconnection sends it.
      host_->Post([value = token->as_string()](Engine& engine) { engine.update_access_token(value); });
      result->Success();
    } else {
      result->Error("bad_arguments", "missing or invalid arguments");
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
    const Json* microphone = arguments.find("micUid");
    std::vector<int> source_pids;
    const Json* pids = arguments.find("sourcePids");
    if (pids != nullptr) {
      for (const Json& pid : pids->as_array()) {
        if (pid.is_number()) source_pids.push_back(static_cast<int>(pid.as_int()));
      }
    }
    host_->StartMeters(microphone != nullptr ? microphone->as_string() : std::string(), std::move(source_pids));
    result->Success();
  } else if (method == "stopMeters") {
    host_->StopMeters();
    result->Success();
  } else if (method == "testTone") {
    const Json* uid = arguments.find("uid");
    if (uid != nullptr && uid->is_string() && !uid->as_string().empty()) {
      // Returns at once; a device that cannot be opened is reported as an `error` event.
      host_->TestTone(uid->as_string());
      result->Success();
    } else {
      result->Error("bad_arguments", "missing or invalid arguments");
    }
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
    result->Success(FromJson(telemetry_->Status()));
  } else if (method == "sendFeedback") {
    const Json* raw = arguments.find("message");
    const std::optional<std::string> message = livebridge::TelemetryUploader::feedback_message(
        raw != nullptr && raw->is_string() ? raw->as_string() : std::string());
    if (!message) {
      result->Error("bad_arguments", "missing or invalid arguments");
      return;
    }
    const Json* email = arguments.find("email");
    const Json* rating = arguments.find("rating");
    std::optional<int> stars;
    if (rating != nullptr && rating->is_number()) stars = static_cast<int>(rating->as_int());
    // Answered later, on the platform thread, from DrainEvents().
    std::shared_ptr<flutter::MethodResult<EncodableValue>> reply = std::move(result);
    telemetry_->SendFeedback(*message, email != nullptr && email->is_string() ? email->as_string() : std::string(),
                             stars, [this, reply](const std::string& code) {
                               {
                                 std::lock_guard<std::mutex> lock(pending_mutex_);
                                 replies_.emplace_back(reply, code);
                               }
                               RequestDrain();
                             });
  } else if (method == "saveTextFile") {
    const Json* content = arguments.find("content");
    if (content == nullptr || !content->is_string()) {
      result->Error("bad_arguments", "missing or invalid arguments");
      return;
    }
    const Json* name = arguments.find("suggestedName");
    const std::string suggested = name != nullptr && name->is_string() ? name->as_string() : "livebridge.md";
    const std::optional<std::wstring> path =
        file_dialogs::ShowSaveDialog(window_, Utf16FromUtf8(suggested), L"Markdown", L"*.md");
    if (!path) {
      result->Success();  // the user cancelled
    } else if (!file_dialogs::WriteUtf8File(*path, content->as_string())) {
      result->Error("save_failed", "The file could not be written.");
    } else {
      result->Success(EncodableValue(Utf8FromUtf16(path->c_str())));
    }
  } else if (method == "analyticsExport") {
    SYSTEMTIME today = {};
    ::GetLocalTime(&today);
    wchar_t name[64] = {};
    swprintf_s(name, L"livebridge-analytics-%04u-%02u-%02u.jsonl", static_cast<unsigned>(today.wYear),
               static_cast<unsigned>(today.wMonth), static_cast<unsigned>(today.wDay));
    const std::optional<std::wstring> path = file_dialogs::ShowSaveDialog(window_, name, L"JSON Lines", L"*.jsonl");
    if (!path) {
      result->Success();  // the user cancelled
    } else if (!file_dialogs::CopyFileTo(analytics_.path().wstring(), *path)) {
      result->Error("save_failed", "The file could not be written.");
    } else {
      result->Success(EncodableValue(Utf8FromUtf16(path->c_str())));
    }
  } else {
    result->NotImplemented();
  }
}
