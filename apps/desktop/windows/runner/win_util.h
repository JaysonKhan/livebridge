#ifndef RUNNER_WIN_UTIL_H_
#define RUNNER_WIN_UTIL_H_

#include <filesystem>
#include <string>

// Small helpers shared by the Windows audio, network and bridge code.

// UTF-8 to UTF-16, for the wide Win32 functions. Empty when the text is empty or is not valid UTF-8. The way back
// is Utf8FromUtf16 in utils.h.
std::wstring Utf16FromUtf8(const std::string& utf8);

// %APPDATA%\LiveBridge: the folder of the saved settings and of the analytics log.
std::filesystem::path AppDataFolder();

// An HRESULT or another 32-bit system code as text for an error message: "0x88890004".
std::string HexCode(unsigned long code);

#endif  // RUNNER_WIN_UTIL_H_
