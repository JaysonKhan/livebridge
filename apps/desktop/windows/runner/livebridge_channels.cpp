#include "livebridge_channels.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <cmath>
#include <cstdint>
#include <set>
#include <string>
#include <utility>
#include <variant>

#include "livebridge/json.h"
#include "settings_store.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using livebridge::Json;

Json ToJson(const EncodableValue& value) {
  if (const auto* boolean = std::get_if<bool>(&value)) return Json(*boolean);
  if (const auto* small = std::get_if<std::int32_t>(&value)) return Json(static_cast<long long>(*small));
  if (const auto* large = std::get_if<std::int64_t>(&value)) return Json(static_cast<long long>(*large));
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

// Methods that have nothing to do until the audio engine exists; they succeed so the interface stays usable.
const std::set<std::string> kNothingToDoYet = {
    "startMeters", "stopMeters",       "testTone",              "stop",     "pttDown", "pttUp",
    "panic",       "setOutgoingMuted", "setIncomingAudioMuted", "setBypass", "rateTurn", "analyticsClear",
    "saveTextFile", "analyticsExport",
};

}  // namespace

LiveBridgeChannels::LiveBridgeChannels(flutter::BinaryMessenger* messenger) {
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
}

LiveBridgeChannels::~LiveBridgeChannels() {
  control_->SetMethodCallHandler(nullptr);
  events_->SetStreamHandler(nullptr);
}

void LiveBridgeChannels::HandleMethodCall(const flutter::MethodCall<EncodableValue>& call,
                                          std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "loadSettings") {
    result->Success(FromJson(settings_store::Load()));
  } else if (method == "saveSettings") {
    if (call.arguments()) settings_store::Save(ToJson(*call.arguments()));
    result->Success();
  } else if (method == "listDevices" || method == "listAudioProcesses") {
    result->Success(EncodableValue(EncodableList{}));
  } else if (method == "microphonePermission") {
    result->Success(EncodableValue("granted"));
  } else if (method == "requestMicrophonePermission") {
    result->Success(EncodableValue(true));
  } else if (method == "languageNames") {
    // No names from the system yet: the app falls back to its own and to the English ones.
    result->Success(EncodableValue(EncodableMap{}));
  } else if (method == "analyticsSummary" || method == "telemetryStatus") {
    result->Success(EncodableValue(EncodableMap{{EncodableValue("enabled"), EncodableValue(false)}}));
  } else if (method == "start") {
    result->Error("unsupported", "The Windows audio engine is not ready yet: sessions cannot start in this build.");
  } else if (method == "sendFeedback") {
    result->Error("feedback_failed", "Feedback cannot be sent from the Windows build yet.");
  } else if (kNothingToDoYet.count(method) > 0) {
    result->Success();
  } else {
    result->NotImplemented();
  }
}
