#ifndef RUNNER_FILE_DIALOGS_H_
#define RUNNER_FILE_DIALOGS_H_

#include <windows.h>

#include <optional>
#include <string>

// The system Save dialog and the file writes behind the bridge's two export methods (docs/bridge-contract.md):
// nothing is written without the user choosing where.
//
// Threads: platform (UI) thread only — COM is initialised there as a single-threaded apartment (main.cpp), and the
// dialog is modal to `owner` (it runs its own message loop, so Flutter keeps drawing while it is open).
//
// How the bridge (livebridge_channels.cpp) uses it — the Windows twin of `save(suggestedName:)` in
// MainFlutterWindow.swift; a cancelled dialog answers null, a failed write `save_failed`:
//
//   `saveTextFile`:
//     const Json* content = arguments.find("content");
//     if (content == nullptr || !content->is_string()) return result->Error("bad_arguments", "...");
//     const Json* name = arguments.find("suggestedName");
//     const std::string suggested = name != nullptr && name->is_string() ? name->as_string() : "livebridge.md";
//     const auto path = file_dialogs::ShowSaveDialog(window_, Utf16FromUtf8(suggested), L"Markdown", L"*.md");
//     if (!path) return result->Success();
//     if (!file_dialogs::WriteUtf8File(*path, content->as_string()))
//       return result->Error("save_failed", "The file could not be written.");
//     result->Success(EncodableValue(Utf8FromUtf16(path->c_str())));
//
//   `analyticsExport` (suggested name with today's local date, like macOS):
//     SYSTEMTIME today = {};
//     ::GetLocalTime(&today);
//     wchar_t name[64];
//     swprintf_s(name, L"livebridge-analytics-%04u-%02u-%02u.jsonl", static_cast<unsigned>(today.wYear),
//                static_cast<unsigned>(today.wMonth), static_cast<unsigned>(today.wDay));
//     const auto path = file_dialogs::ShowSaveDialog(window_, name, L"JSON Lines", L"*.jsonl");
//     if (!path) return result->Success();
//     if (!file_dialogs::CopyFileTo(analytics_.path().wstring(), *path))
//       return result->Error("save_failed", "The file could not be written.");
//     result->Success(EncodableValue(Utf8FromUtf16(path->c_str())));
//
//   (Then drop both names from kNotOnWindowsYet.)
namespace file_dialogs {

// Shows the Save dialog with `suggested_name` filled in and one file type (`filter_name`, e.g. L"Markdown", for
// `filter_pattern`, e.g. L"*.md", whose extension is added to a name typed without one). Asks before replacing an
// existing file. Returns the chosen file-system path, or nullopt when the user cancelled (or the dialog could not be
// shown).
std::optional<std::wstring> ShowSaveDialog(HWND owner, const std::wstring& suggested_name,
                                           const std::wstring& filter_name, const std::wstring& filter_pattern);

// Writes `content` (UTF-8 text, written as is, no byte-order mark) to `path`, replacing the file in one step: it is
// written beside it first and then renamed over it. False when that failed; the old file is then untouched.
bool WriteUtf8File(const std::wstring& path, const std::string& content);

// Copies the file `from` to `to` the same way (a missing `from` gives an empty file, as on macOS: an empty log).
bool CopyFileTo(const std::wstring& from, const std::wstring& to);

}  // namespace file_dialogs

#endif  // RUNNER_FILE_DIALOGS_H_
