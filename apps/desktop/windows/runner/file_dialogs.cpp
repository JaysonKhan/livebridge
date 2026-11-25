#include "file_dialogs.h"

#include <windows.h>

#include <objbase.h>
#include <shobjidl.h>

#include <algorithm>
#include <cstddef>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace file_dialogs {
namespace {

// WriteFile takes at most a DWORD of bytes per call.
const DWORD kWriteChunkBytes = 1u << 20;

// "md" for L"*.md" (the first pattern of a list like L"*.md;*.txt"); empty for L"*.*" or a pattern without one.
std::wstring ExtensionOf(const std::wstring& pattern) {
  const std::wstring first = pattern.substr(0, pattern.find(L';'));
  const std::size_t dot = first.rfind(L'.');
  if (dot == std::wstring::npos) return std::wstring();
  const std::wstring extension = first.substr(dot + 1);
  return extension.find_first_of(L"*?") == std::wstring::npos ? extension : std::wstring();
}

// Writes `bytes` beside `path` and renames the result over it, so that `path` is either the old file or the whole
// new one.
bool ReplaceWith(const std::wstring& path, const std::string& bytes) {
  const std::wstring temporary = path + L".livebridge-tmp";
  const HANDLE file = ::CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                    FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  bool written = true;
  std::size_t done = 0;
  while (written && done < bytes.size()) {
    const DWORD chunk = static_cast<DWORD>(std::min(bytes.size() - done, static_cast<std::size_t>(kWriteChunkBytes)));
    DWORD wrote = 0;
    written = ::WriteFile(file, bytes.data() + done, chunk, &wrote, nullptr) != FALSE && wrote == chunk;
    done += wrote;
  }
  ::CloseHandle(file);
  if (written && ::MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    return true;
  }
  ::DeleteFileW(temporary.c_str());
  return false;
}

}  // namespace

std::optional<std::wstring> ShowSaveDialog(HWND owner, const std::wstring& suggested_name,
                                           const std::wstring& filter_name, const std::wstring& filter_pattern) {
  IFileSaveDialog* dialog = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return std::nullopt;
  }
  const COMDLG_FILTERSPEC types[] = {{filter_name.c_str(), filter_pattern.c_str()}};
  dialog->SetFileTypes(1, types);
  dialog->SetFileTypeIndex(1);
  const std::wstring extension = ExtensionOf(filter_pattern);
  if (!extension.empty()) dialog->SetDefaultExtension(extension.c_str());
  dialog->SetFileName(suggested_name.c_str());
  // Only places with a file-system path (an export is written with plain file calls); the defaults of a Save
  // dialog already include asking before an existing file is replaced.
  FILEOPENDIALOGOPTIONS chosen_options = 0;
  if (SUCCEEDED(dialog->GetOptions(&chosen_options))) {
    dialog->SetOptions(chosen_options | static_cast<FILEOPENDIALOGOPTIONS>(FOS_FORCEFILESYSTEM) |
                       static_cast<FILEOPENDIALOGOPTIONS>(FOS_OVERWRITEPROMPT));
  }

  std::optional<std::wstring> path;
  // Show() fails with HRESULT_FROM_WIN32(ERROR_CANCELLED) when the user cancels.
  if (SUCCEEDED(dialog->Show(owner))) {
    IShellItem* item = nullptr;
    if (SUCCEEDED(dialog->GetResult(&item))) {
      PWSTR chosen = nullptr;
      if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &chosen))) {
        path = std::wstring(chosen);
        ::CoTaskMemFree(chosen);
      }
      item->Release();
    }
  }
  dialog->Release();
  return path;
}

bool WriteUtf8File(const std::wstring& path, const std::string& content) { return ReplaceWith(path, content); }

bool CopyFileTo(const std::wstring& from, const std::wstring& to) {
  std::ifstream in(std::filesystem::path(from), std::ios::binary);
  std::ostringstream bytes;
  if (in) bytes << in.rdbuf();
  return ReplaceWith(to, bytes.str());
}

}  // namespace file_dialogs
