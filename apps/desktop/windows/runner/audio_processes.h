#ifndef RUNNER_AUDIO_PROCESSES_H_
#define RUNNER_AUDIO_PROCESSES_H_

#include "livebridge/json.h"

// The processes that have an audio session on an active playback endpoint: the candidates for the meeting source
// (the Windows twin of AudioProcesses in ProcessTap.swift).
//
// COM must be initialised on the calling thread; either kind of apartment will do.
namespace audio_processes {

// The `listAudioProcesses` result of docs/bridge-contract.md: one map per process - `pid`, `bundleId` (the executable's
// file name in lower case, "chrome.exe"), `name` (the file name without ".exe") and `isPlaying` - with the ones playing
// right now first, then by name. System sounds and this app are left out.
livebridge::Json ListForBridge();

}  // namespace audio_processes

#endif  // RUNNER_AUDIO_PROCESSES_H_
