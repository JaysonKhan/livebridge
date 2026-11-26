#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "scoped_handle.h"
#include "utils.h"

namespace {

// The main window's title; a second launch finds the running window by it and
// by the window class win32_window.cpp registers.
constexpr const wchar_t kWindowTitle[] = L"JK - LiveBridge";

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One window per user session: two would both refresh the account's token,
  // and the site signs this computer out when a retired one comes back. A
  // second launch brings the running window to the front instead.
  ScopedHandle single_instance(
      ::CreateMutexW(nullptr, FALSE, L"Local\\JK-LiveBridge-single-instance"));
  if (single_instance.get() != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND running =
        ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
    if (running != nullptr) {
      if (::IsIconic(running)) ::ShowWindow(running, SW_RESTORE);
      ::SetForegroundWindow(running);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
