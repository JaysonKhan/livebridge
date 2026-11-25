// A small JSON value for the gateway's control messages and the numbers-only analytics log.
// Parsing is strict (RFC 8259), bounded in depth, and never throws.
#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace livebridge {

class Json {
 public:
  using Array = std::vector<Json>;
  /// Insertion order is kept; keys are looked up linearly (messages are small).
  using Object = std::vector<std::pair<std::string, Json>>;

  Json() = default;
  Json(std::nullptr_t) {}
  Json(bool value) : value_(value) {}
  Json(double value) : value_(value) {}
  Json(int value) : value_(static_cast<double>(value)) {}
  Json(long long value) : value_(static_cast<double>(value)) {}
  Json(unsigned long long value) : value_(static_cast<double>(value)) {}
  Json(const char* value) : value_(std::string(value)) {}
  Json(std::string value) : value_(std::move(value)) {}
  Json(Array value) : value_(std::move(value)) {}
  Json(Object value) : value_(std::move(value)) {}

  bool is_null() const { return std::holds_alternative<std::monostate>(value_); }
  bool is_bool() const { return std::holds_alternative<bool>(value_); }
  bool is_number() const { return std::holds_alternative<double>(value_); }
  bool is_string() const { return std::holds_alternative<std::string>(value_); }
  bool is_array() const { return std::holds_alternative<Array>(value_); }
  bool is_object() const { return std::holds_alternative<Object>(value_); }

  /// Typed reads with a fallback for a missing or differently typed value.
  bool as_bool(bool fallback = false) const { return is_bool() ? std::get<bool>(value_) : fallback; }
  double as_number(double fallback = 0) const { return is_number() ? std::get<double>(value_) : fallback; }
  long long as_int(long long fallback = 0) const;
  const std::string& as_string() const;
  const Array& as_array() const;
  const Object& as_object() const;

  /// The member `key` of an object, or nullptr (also when this is not an object).
  const Json* find(std::string_view key) const;
  /// Adds or replaces a member; a value that is not an object becomes an empty object first.
  void set(std::string key, Json value);

  /// Compact UTF-8 text. Integral numbers are written without a fraction.
  std::string dump() const;

  /// Returns false (and sets `error` when given) on malformed input; `out` is then unspecified.
  static bool parse(std::string_view text, Json& out, std::string* error = nullptr);

  bool operator==(const Json& other) const { return value_ == other.value_; }
  bool operator!=(const Json& other) const { return !(*this == other); }

 private:
  std::variant<std::monostate, bool, double, std::string, Array, Object> value_;
};

}  // namespace livebridge
