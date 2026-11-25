#include "settings_store.h"

#include <windows.h>

#include <shlobj.h>
#include <wincred.h>

#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace settings_store {
namespace {

const wchar_t kTokenTarget[] = L"JK-LiveBridge/gateway-access-token";
const char kTokenKey[] = "accessToken";

std::filesystem::path SettingsFile() {
  PWSTR raw = nullptr;
  std::filesystem::path folder;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &raw))) folder = raw;
  CoTaskMemFree(raw);
  return folder / L"LiveBridge" / L"settings.json";
}

livebridge::Json LoadPreferences() {
  std::ifstream file(SettingsFile(), std::ios::binary);
  std::stringstream text;
  text << file.rdbuf();
  livebridge::Json saved;
  if (!livebridge::Json::parse(text.str(), saved) || !saved.is_object()) saved = livebridge::Json::Object{};
  return saved;
}

std::string ReadToken() {
  PCREDENTIALW credential = nullptr;
  if (!CredReadW(kTokenTarget, CRED_TYPE_GENERIC, 0, &credential)) return {};
  std::string token(reinterpret_cast<const char*>(credential->CredentialBlob), credential->CredentialBlobSize);
  CredFree(credential);
  return token;
}

void WriteToken(const std::string& token) {
  if (token.empty()) {
    CredDeleteW(kTokenTarget, CRED_TYPE_GENERIC, 0);
    return;
  }
  wchar_t user[] = L"LiveBridge";
  CREDENTIALW credential = {};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<LPWSTR>(kTokenTarget);
  credential.CredentialBlobSize = static_cast<DWORD>(token.size());
  credential.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char*>(token.data()));
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  credential.UserName = user;
  CredWriteW(&credential, 0);
}

}  // namespace

livebridge::Json Load() {
  livebridge::Json saved = LoadPreferences();
  const std::string token = ReadToken();
  if (!token.empty()) saved.set(kTokenKey, token);
  return saved;
}

void Save(const livebridge::Json& changes) {
  livebridge::Json saved = LoadPreferences();
  for (const auto& [key, value] : changes.as_object()) {
    if (key == kTokenKey) {
      WriteToken(value.as_string());
    } else {
      saved.set(key, value);
    }
  }
  const std::filesystem::path file = SettingsFile();
  std::error_code ignored;
  std::filesystem::create_directories(file.parent_path(), ignored);
  std::ofstream out(file, std::ios::binary | std::ios::trunc);
  out << saved.dump();
}

}  // namespace settings_store
