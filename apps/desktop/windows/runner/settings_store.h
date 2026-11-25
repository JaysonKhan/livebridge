#ifndef RUNNER_SETTINGS_STORE_H_
#define RUNNER_SETTINGS_STORE_H_

#include "livebridge/json.h"

// Saved settings on Windows. Preferences are a JSON object in %APPDATA%\LiveBridge\settings.json; the gateway
// access token is kept out of that file, in the Windows Credential Manager.
namespace settings_store {

// Everything saved, as one object (`accessToken` included when one is stored). Empty when nothing was saved.
livebridge::Json Load();

// Merges the members of `changes` (an object) into what is saved.
void Save(const livebridge::Json& changes);

}  // namespace settings_store

#endif  // RUNNER_SETTINGS_STORE_H_
