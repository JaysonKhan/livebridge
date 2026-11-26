#include "settings_store.h"

#include <windows.h>

#include <shlobj.h>
#include <wincred.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace settings_store {
namespace {

// A settings key and the Credential Manager target that holds it. These keys never reach the preferences file.
struct Secret {
  const char* key;
  const wchar_t* target;
};

const Secret kSecrets[] = {
    {"accessToken", L"JK-LiveBridge/gateway-access-token"},
    {"accountRefreshToken", L"JK-LiveBridge/account-refresh-token"},
    {"elevenlabsApiKey", L"JK-LiveBridge/elevenlabs-api-key"},
    {"geminiApiKey", L"JK-LiveBridge/gemini-api-key"},
};

// The target of a secret's key; null for a preference.
const wchar_t* SecretTarget(const std::string& key) {
  for (const Secret& secret : kSecrets) {
    if (key == secret.key) return secret.target;
  }
  return nullptr;
}

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

std::string ReadSecret(const wchar_t* target) {
  PCREDENTIALW credential = nullptr;
  if (!CredReadW(target, CRED_TYPE_GENERIC, 0, &credential)) return {};
  std::string secret(reinterpret_cast<const char*>(credential->CredentialBlob), credential->CredentialBlobSize);
  CredFree(credential);
  return secret;
}

// Stores `secret` in place of what was there (CredWriteW replaces it whole, so a failed write leaves the old value);
// an empty one deletes the credential. False when that failed. Deleting a credential that does not exist succeeds.
bool WriteSecret(const wchar_t* target, const std::string& secret) {
  if (secret.empty()) return CredDeleteW(target, CRED_TYPE_GENERIC, 0) != FALSE || GetLastError() == ERROR_NOT_FOUND;
  wchar_t user[] = L"LiveBridge";
  CREDENTIALW credential = {};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<LPWSTR>(target);
  credential.CredentialBlobSize = static_cast<DWORD>(secret.size());
  credential.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char*>(secret.data()));
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  credential.UserName = user;
  return CredWriteW(&credential, 0) != FALSE;
}

}  // namespace

livebridge::Json Load() {
  livebridge::Json saved = LoadPreferences();
  for (const Secret& secret : kSecrets) {
    const std::string value = ReadSecret(secret.target);
    if (!value.empty()) saved.set(secret.key, value);
  }
  return saved;
}

std::vector<std::string> Save(const livebridge::Json& changes) {
  livebridge::Json saved = LoadPreferences();
  std::vector<std::string> failed;
  for (const auto& [key, value] : changes.as_object()) {
    const wchar_t* target = SecretTarget(key);
    if (target == nullptr) {
      saved.set(key, value);
      continue;
    }
    // A secret is written, or deleted when it is null (which reads as the empty string); any other type is ignored.
    if ((value.is_null() || value.is_string()) && !WriteSecret(target, value.as_string())) failed.push_back(key);
  }
  std::sort(failed.begin(), failed.end());
  const std::filesystem::path file = SettingsFile();
  std::error_code ignored;
  std::filesystem::create_directories(file.parent_path(), ignored);
  std::ofstream out(file, std::ios::binary | std::ios::trunc);
  out << saved.dump();
  return failed;
}

}  // namespace settings_store
