#include "livebridge/json.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace livebridge {
namespace {

const int kMaxDepth = 64;

void append_utf8(unsigned code, std::string& out) {
  if (code < 0x80) {
    out += static_cast<char>(code);
  } else if (code < 0x800) {
    out += static_cast<char>(0xC0 | (code >> 6));
    out += static_cast<char>(0x80 | (code & 0x3F));
  } else if (code < 0x10000) {
    out += static_cast<char>(0xE0 | (code >> 12));
    out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
    out += static_cast<char>(0x80 | (code & 0x3F));
  } else {
    out += static_cast<char>(0xF0 | (code >> 18));
    out += static_cast<char>(0x80 | ((code >> 12) & 0x3F));
    out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
    out += static_cast<char>(0x80 | (code & 0x3F));
  }
}

class Parser {
 public:
  explicit Parser(std::string_view text) : text_(text) {}

  bool run(Json& out, std::string* error) {
    skip_space();
    if (!value(out, 0)) return fail(error);
    skip_space();
    if (at_ != text_.size()) {
      message_ = "unexpected text after the value";
      return fail(error);
    }
    return true;
  }

 private:
  bool fail(std::string* error) {
    if (error) *error = message_ + " at offset " + std::to_string(at_);
    return false;
  }

  bool bad(const char* message) {
    message_ = message;
    return false;
  }

  void skip_space() {
    while (at_ < text_.size() && (text_[at_] == ' ' || text_[at_] == '\t' || text_[at_] == '\n' || text_[at_] == '\r')) at_++;
  }

  bool literal(std::string_view word) {
    if (text_.substr(at_, word.size()) != word) return bad("unknown literal");
    at_ += word.size();
    return true;
  }

  bool hex4(unsigned& code) {
    if (at_ + 4 > text_.size()) return bad("short \\u escape");
    code = 0;
    for (int i = 0; i < 4; i++) {
      const char c = text_[at_++];
      code <<= 4;
      if (c >= '0' && c <= '9') code |= static_cast<unsigned>(c - '0');
      else if (c >= 'a' && c <= 'f') code |= static_cast<unsigned>(c - 'a' + 10);
      else if (c >= 'A' && c <= 'F') code |= static_cast<unsigned>(c - 'A' + 10);
      else return bad("bad \\u escape");
    }
    return true;
  }

  bool string(std::string& out) {
    at_++;  // opening quote
    while (true) {
      if (at_ >= text_.size()) return bad("unterminated string");
      const unsigned char c = static_cast<unsigned char>(text_[at_++]);
      if (c == '"') return true;
      if (c < 0x20) return bad("control character in string");
      if (c != '\\') {
        out += static_cast<char>(c);
        continue;
      }
      if (at_ >= text_.size()) return bad("unterminated escape");
      switch (text_[at_++]) {
        case '"': out += '"'; break;
        case '\\': out += '\\'; break;
        case '/': out += '/'; break;
        case 'b': out += '\b'; break;
        case 'f': out += '\f'; break;
        case 'n': out += '\n'; break;
        case 'r': out += '\r'; break;
        case 't': out += '\t'; break;
        case 'u': {
          unsigned code = 0;
          if (!hex4(code)) return false;
          if (code >= 0xD800 && code <= 0xDBFF) {
            // A high surrogate must be followed by a low one; together they are one code point.
            unsigned low = 0;
            if (text_.substr(at_, 2) != "\\u") return bad("lone surrogate");
            at_ += 2;
            if (!hex4(low)) return false;
            if (low < 0xDC00 || low > 0xDFFF) return bad("lone surrogate");
            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
          } else if (code >= 0xDC00 && code <= 0xDFFF) {
            return bad("lone surrogate");
          }
          append_utf8(code, out);
          break;
        }
        default: return bad("unknown escape");
      }
    }
  }

  bool number(Json& out) {
    const std::size_t start = at_;
    auto digits = [&] {
      const std::size_t before = at_;
      while (at_ < text_.size() && text_[at_] >= '0' && text_[at_] <= '9') at_++;
      return at_ > before;
    };
    if (at_ < text_.size() && text_[at_] == '-') at_++;
    if (at_ < text_.size() && text_[at_] == '0') at_++;
    else if (!digits()) return bad("bad number");
    if (at_ < text_.size() && text_[at_] == '.') {
      at_++;
      if (!digits()) return bad("bad number");
    }
    if (at_ < text_.size() && (text_[at_] == 'e' || text_[at_] == 'E')) {
      at_++;
      if (at_ < text_.size() && (text_[at_] == '+' || text_[at_] == '-')) at_++;
      if (!digits()) return bad("bad number");
    }
    const std::string token(text_.substr(start, at_ - start));
    out = Json(std::strtod(token.c_str(), nullptr));
    return true;
  }

  bool value(Json& out, int depth) {
    if (depth > kMaxDepth) return bad("nested too deeply");
    if (at_ >= text_.size()) return bad("unexpected end");
    switch (text_[at_]) {
      case 'n':
        out = Json();
        return literal("null");
      case 't':
        out = Json(true);
        return literal("true");
      case 'f':
        out = Json(false);
        return literal("false");
      case '"': {
        std::string text;
        if (!string(text)) return false;
        out = Json(std::move(text));
        return true;
      }
      case '[': {
        at_++;
        Json::Array items;
        skip_space();
        if (at_ < text_.size() && text_[at_] == ']') {
          at_++;
        } else {
          while (true) {
            Json item;
            skip_space();
            if (!value(item, depth + 1)) return false;
            items.push_back(std::move(item));
            skip_space();
            if (at_ >= text_.size()) return bad("unterminated array");
            const char c = text_[at_++];
            if (c == ']') break;
            if (c != ',') return bad("expected , or ]");
          }
        }
        out = Json(std::move(items));
        return true;
      }
      case '{': {
        at_++;
        Json::Object members;
        skip_space();
        if (at_ < text_.size() && text_[at_] == '}') {
          at_++;
        } else {
          while (true) {
            skip_space();
            if (at_ >= text_.size() || text_[at_] != '"') return bad("expected a member name");
            std::string key;
            if (!string(key)) return false;
            skip_space();
            if (at_ >= text_.size() || text_[at_++] != ':') return bad("expected :");
            skip_space();
            Json member;
            if (!value(member, depth + 1)) return false;
            members.emplace_back(std::move(key), std::move(member));
            skip_space();
            if (at_ >= text_.size()) return bad("unterminated object");
            const char c = text_[at_++];
            if (c == '}') break;
            if (c != ',') return bad("expected , or }");
          }
        }
        out = Json(std::move(members));
        return true;
      }
      default:
        if (text_[at_] == '-' || (text_[at_] >= '0' && text_[at_] <= '9')) return number(out);
        return bad("unexpected character");
    }
  }

  std::string_view text_;
  std::size_t at_ = 0;
  std::string message_ = "invalid JSON";
};

void dump_string(const std::string& text, std::string& out) {
  out += '"';
  for (const char raw : text) {
    const unsigned char c = static_cast<unsigned char>(raw);
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\b': out += "\\b"; break;
      case '\f': out += "\\f"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char buffer[8];
          std::snprintf(buffer, sizeof(buffer), "\\u%04x", static_cast<unsigned>(c));
          out += buffer;
        } else {
          out += raw;
        }
    }
  }
  out += '"';
}

void dump_value(const Json& value, std::string& out) {
  if (value.is_null()) {
    out += "null";
  } else if (value.is_bool()) {
    out += value.as_bool() ? "true" : "false";
  } else if (value.is_number()) {
    const double number = value.as_number();
    char buffer[32];
    if (!std::isfinite(number)) {
      out += "null";  // JSON has no NaN or infinity
    } else if (number == std::floor(number) && std::fabs(number) < 9.007199254740992e15) {
      std::snprintf(buffer, sizeof(buffer), "%.0f", number);
      out += buffer;
    } else {
      std::snprintf(buffer, sizeof(buffer), "%.17g", number);
      out += buffer;
    }
  } else if (value.is_string()) {
    dump_string(value.as_string(), out);
  } else if (value.is_array()) {
    out += '[';
    bool first = true;
    for (const Json& item : value.as_array()) {
      if (!first) out += ',';
      first = false;
      dump_value(item, out);
    }
    out += ']';
  } else {
    out += '{';
    bool first = true;
    for (const auto& [key, member] : value.as_object()) {
      if (!first) out += ',';
      first = false;
      dump_string(key, out);
      out += ':';
      dump_value(member, out);
    }
    out += '}';
  }
}

}  // namespace

long long Json::as_int(long long fallback) const {
  return is_number() ? static_cast<long long>(std::llround(std::get<double>(value_))) : fallback;
}

const std::string& Json::as_string() const {
  static const std::string empty;
  return is_string() ? std::get<std::string>(value_) : empty;
}

const Json::Array& Json::as_array() const {
  static const Array empty;
  return is_array() ? std::get<Array>(value_) : empty;
}

const Json::Object& Json::as_object() const {
  static const Object empty;
  return is_object() ? std::get<Object>(value_) : empty;
}

const Json* Json::find(std::string_view key) const {
  if (!is_object()) return nullptr;
  for (const auto& member : std::get<Object>(value_))
    if (member.first == key) return &member.second;
  return nullptr;
}

void Json::set(std::string key, Json value) {
  if (!is_object()) value_ = Object{};
  auto& members = std::get<Object>(value_);
  for (auto& member : members) {
    if (member.first == key) {
      member.second = std::move(value);
      return;
    }
  }
  members.emplace_back(std::move(key), std::move(value));
}

std::string Json::dump() const {
  std::string out;
  dump_value(*this, out);
  return out;
}

bool Json::parse(std::string_view text, Json& out, std::string* error) {
  return Parser(text).run(out, error);
}

}  // namespace livebridge
