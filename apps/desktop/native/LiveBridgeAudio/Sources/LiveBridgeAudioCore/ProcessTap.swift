import AppKit
import CoreAudio
import Foundation

public struct AudioProcessInfo: Equatable, Sendable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleId: String
    public let name: String
    public let isPlaying: Bool

    public var dictionary: [String: Any] {
        ["pid": Int(pid), "bundleId": bundleId, "name": name, "isPlaying": isPlaying]
    }
}

public enum AudioProcesses {
    /// Processes that currently own a Core Audio process object — meeting apps and browser audio helpers appear
    /// here once they have opened an audio device. This app itself is left out.
    public static func all() -> [AudioProcessInfo] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let own = ProcessInfo.processInfo.processIdentifier
        return HAL.array(system, kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self).compactMap { object in
            guard let pid = HAL.value(object, kAudioProcessPropertyPID, default: pid_t(0)), pid > 0, pid != own
            else { return nil }
            let bundleId = HAL.string(object, kAudioProcessPropertyBundleID) ?? ""
            let name = [NSRunningApplication(processIdentifier: pid)?.localizedName, processName(pid), bundleId]
                .compactMap { $0 }.first { !$0.isEmpty } ?? "pid \(pid)"
            let playing = HAL.value(object, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) ?? 0
            return AudioProcessInfo(objectID: object, pid: pid, bundleId: bundleId, name: name, isPlaying: playing != 0)
        }
        .sorted { ($0.isPlaying ? 0 : 1, $0.name.lowercased()) < ($1.isPlaying ? 0 : 1, $1.name.lowercased()) }
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        return proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
    }
}

/// A Core Audio process tap on the selected meeting processes only (never the whole system), exposed as a private
/// aggregate device that `CaptureSource` reads like any input device. Requires macOS 14.2 and the user's
/// "System Audio Recording" permission (`NSAudioCaptureUsageDescription`); without it the tap delivers silence.
///
/// The tapped apps keep playing to their own output device (`muteBehavior = .unmuted`), so the user still hears
/// the original speech alongside the translation.
public final class ProcessTap {
    public let deviceID: AudioObjectID
    public let pids: [pid_t]
    private let tapID: AudioObjectID

    public init(pids: [pid_t]) throws {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var objects: [AudioObjectID] = []
        for pid in pids {
            var address = HAL.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            var qualifier = pid
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var object = AudioObjectID(kAudioObjectUnknown)
            let status = AudioObjectGetPropertyData(
                system, &address, UInt32(MemoryLayout<pid_t>.size), &qualifier, &size, &object)
            guard status == noErr, object != kAudioObjectUnknown else {
                // A stale pid (the app quit, or it has not opened audio yet) is an error, not a silent no-op.
                throw AudioEngineError("source_gone", "process \(pid) is not running or has no audio; pick the meeting app again")
            }
            objects.append(object)
        }
        guard !objects.isEmpty else { throw AudioEngineError("source_gone", "no meeting process selected") }

        let description = CATapDescription(monoMixdownOfProcesses: objects)
        description.uuid = UUID()
        description.name = "LiveBridge meeting tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr, tap != kAudioObjectUnknown else {
            throw AudioEngineError("tap", "could not create the process tap (OSStatus \(status))")
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LiveBridge meeting tap",
            kAudioAggregateDeviceUIDKey: "livebridge.tap.\(UUID().uuidString)",
            // Private: invisible to other apps and removed automatically if this process dies.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
            ],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tap)
            throw AudioEngineError("tap", "could not create the tap capture device (OSStatus \(status))")
        }
        tapID = tap
        deviceID = device
        self.pids = pids
    }

    deinit {
        AudioHardwareDestroyAggregateDevice(deviceID)
        AudioHardwareDestroyProcessTap(tapID)
    }

    /// True while every tapped process still exists.
    public var isAlive: Bool {
        let live = Set(AudioProcesses.all().map(\.pid))
        return pids.allSatisfy(live.contains)
    }
}
