#include "audio_processes.h"

#include <windows.h>

#include <objbase.h>

#include <audioclient.h>
#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <map>
#include <string>
#include <utility>
#include <vector>

#include "utils.h"

namespace audio_processes {
namespace {

using Microsoft::WRL::ComPtr;
using livebridge::Json;

struct Process {
  DWORD pid = 0;
  bool playing = false;
  std::string name;
  std::string bundle_id;
  // The name in lower case, for sorting.
  std::wstring sort_name;
};

// Adds every process with an audio session on this endpoint to `playing`, and whether one of its sessions is playing
// right now. System sounds, sessions shared by several processes and expired sessions (their process has gone) are
// skipped.
void CollectSessions(IMMDevice* device, std::map<DWORD, bool>& playing) {
  ComPtr<IAudioSessionManager2> manager;
  ComPtr<IAudioSessionEnumerator> sessions;
  int session_total = 0;
  if (FAILED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr,
                              reinterpret_cast<void**>(manager.GetAddressOf()))) ||
      FAILED(manager->GetSessionEnumerator(sessions.GetAddressOf())) || FAILED(sessions->GetCount(&session_total))) {
    return;
  }
  for (int i = 0; i < session_total; i++) {
    ComPtr<IAudioSessionControl> control;
    ComPtr<IAudioSessionControl2> details;
    DWORD pid = 0;
    AudioSessionState session_state = AudioSessionStateInactive;
    // GetProcessId answers AUDCLNT_S_NO_SINGLE_PROCESS (a success code) for a session of several processes.
    if (FAILED(sessions->GetSession(i, control.GetAddressOf())) || FAILED(control.As(&details)) ||
        details->IsSystemSoundsSession() == S_OK || details->GetProcessId(&pid) != S_OK ||
        FAILED(control->GetState(&session_state)) || session_state == AudioSessionStateExpired) {
      continue;
    }
    bool& is_playing = playing[pid];
    is_playing = is_playing || session_state == AudioSessionStateActive;
  }
}

// The executable's full path; empty when the process cannot be asked (it has ended, or it is protected).
std::wstring ImagePath(DWORD pid) {
  const HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return std::wstring();
  std::wstring path(32'768, L'\0');
  DWORD length = static_cast<DWORD>(path.size());
  const BOOL found = ::QueryFullProcessImageNameW(process, 0, path.data(), &length);
  ::CloseHandle(process);
  if (!found) return std::wstring();
  path.resize(length);
  return path;
}

Process Describe(DWORD pid, bool playing) {
  Process process;
  process.pid = pid;
  process.playing = playing;
  const std::wstring path = ImagePath(pid);
  const std::size_t slash = path.find_last_of(L"\\/");
  std::wstring file = slash == std::wstring::npos ? path : path.substr(slash + 1);
  std::wstring lower = file;
  if (!lower.empty()) ::CharLowerBuffW(lower.data(), static_cast<DWORD>(lower.size()));
  process.bundle_id = Utf8FromUtf16(lower.c_str());

  const std::wstring extension = L".exe";
  if (lower.size() > extension.size() &&
      lower.compare(lower.size() - extension.size(), extension.size(), extension) == 0) {
    file.resize(file.size() - extension.size());
    lower.resize(lower.size() - extension.size());
  }
  if (file.empty()) {
    // Nothing to call it by: the id will have to do.
    file = L"pid " + std::to_wstring(pid);
    lower = file;
  }
  process.name = Utf8FromUtf16(file.c_str());
  process.sort_name = std::move(lower);
  return process;
}

}  // namespace

Json ListForBridge() {
  std::map<DWORD, bool> playing;
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDeviceCollection> endpoints;
  UINT endpoint_total = 0;
  if (SUCCEEDED(::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                   IID_PPV_ARGS(enumerator.GetAddressOf()))) &&
      SUCCEEDED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, endpoints.GetAddressOf())) &&
      SUCCEEDED(endpoints->GetCount(&endpoint_total))) {
    for (UINT i = 0; i < endpoint_total; i++) {
      ComPtr<IMMDevice> endpoint;
      if (SUCCEEDED(endpoints->Item(i, endpoint.GetAddressOf())) && endpoint.Get() != nullptr) {
        CollectSessions(endpoint.Get(), playing);
      }
    }
  }

  const DWORD own = ::GetCurrentProcessId();
  std::vector<Process> processes;
  for (const auto& [pid, is_playing] : playing) {
    if (pid == 0 || pid == own) continue;
    processes.push_back(Describe(pid, is_playing));
  }
  std::sort(processes.begin(), processes.end(), [](const Process& left, const Process& right) {
    if (left.playing != right.playing) return left.playing;
    if (left.sort_name != right.sort_name) return left.sort_name < right.sort_name;
    return left.pid < right.pid;
  });

  Json::Array list;
  for (const Process& process : processes) {
    Json::Object entry;
    entry.emplace_back("pid", static_cast<long long>(process.pid));
    entry.emplace_back("bundleId", process.bundle_id);
    entry.emplace_back("name", process.name);
    entry.emplace_back("isPlaying", process.playing);
    list.push_back(Json(std::move(entry)));
  }
  return Json(std::move(list));
}

}  // namespace audio_processes
