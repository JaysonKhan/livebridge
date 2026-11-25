#include "win_util.h"

#include <windows.h>

#include <shlobj.h>

#include <climits>
#include <cstddef>
#include <cstdio>

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty() || utf8.size() > static_cast<std::size_t>(INT_MAX)) return std::wstring();
  const int bytes = static_cast<int>(utf8.size());
  const int length = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), bytes, nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring utf16(static_cast<std::size_t>(length), L'\0');
  if (::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), bytes, utf16.data(), length) != length) {
    return std::wstring();
  }
  return utf16;
}

std::filesystem::path AppDataFolder() {
  PWSTR raw = nullptr;
  std::filesystem::path folder;
  if (SUCCEEDED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &raw))) folder = raw;
  ::CoTaskMemFree(raw);
  return folder / L"LiveBridge";
}

std::string HexCode(unsigned long code) {
  char text[16];
  std::snprintf(text, sizeof(text), "0x%08lX", code);
  return text;
}
