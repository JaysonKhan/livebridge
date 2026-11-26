#ifndef RUNNER_SETTINGS_STORE_H_
#define RUNNER_SETTINGS_STORE_H_

#include <string>
#include <vector>

#include "livebridge/json.h"

// Saved settings on Windows. Preferences are a JSON object in %APPDATA%\LiveBridge\settings.json; the secrets (the
// static gateway token, the account's refresh token, the provider keys) are kept out of that file, in the Windows
// Credential Manager, one credential each.
namespace settings_store {

// Everything saved, as one object (the secrets that are stored included). Empty when nothing was saved.
livebridge::Json Load();

// Merges the members of `changes` (an object) into what is saved. A secret set to null (or to an empty string) is
// deleted; one that is absent is left alone. Returns the keys of the secrets that could not be written or deleted,
// sorted — never their values. The preferences are saved either way.
std::vector<std::string> Save(const livebridge::Json& changes);

}  // namespace settings_store

#endif  // RUNNER_SETTINGS_STORE_H_
