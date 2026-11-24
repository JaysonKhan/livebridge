import CoreAudio
import Foundation

public struct AudioEngineError: Error, CustomStringConvertible, Sendable {
    public let code: String
    public let message: String
    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
    public var description: String { "\(code): \(message)" }
}

public struct AudioDeviceInfo: Equatable, Sendable {
    public let id: AudioObjectID
    /// Stable across reboots and replugging; this is what settings store, never the numeric id.
    public let uid: String
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int
    public let sampleRate: Double
    public let transport: String
    public let isDefaultInput: Bool
    public let isDefaultOutput: Bool

    public var isVirtual: Bool { transport == "virtual" || transport == "aggregate" }

    public var dictionary: [String: Any] {
        [
            "uid": uid, "name": name, "inputChannels": inputChannels, "outputChannels": outputChannels,
            "sampleRate": sampleRate, "transport": transport, "isDefaultInput": isDefaultInput,
            "isDefaultOutput": isDefaultOutput,
        ]
    }
}

/// Thin typed wrappers over the Core Audio HAL property API.
enum HAL {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, default value: T,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> T? {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        var result = value
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        return status == noErr ? result : nil
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var result: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let result else { return nil }
        return result.takeRetainedValue() as String
    }

    static func array<T>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, of type: T.Type
    ) -> [T] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!)
            initialized = status == noErr ? Int(size) / MemoryLayout<T>.stride : 0
        }
    }

    static func channelCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

public enum AudioDevices {
    public static func all() -> [AudioDeviceInfo] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let defaultInput = HAL.value(system, kAudioHardwarePropertyDefaultInputDevice, default: AudioObjectID(0))
        let defaultOutput = HAL.value(system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
        return HAL.array(system, kAudioHardwarePropertyDevices, of: AudioObjectID.self).compactMap { id in
            guard HAL.value(id, kAudioDevicePropertyDeviceIsAlive, default: UInt32(0)) == 1,
                let uid = HAL.string(id, kAudioDevicePropertyDeviceUID)
            else { return nil }
            return AudioDeviceInfo(
                id: id,
                uid: uid,
                name: HAL.string(id, kAudioObjectPropertyName) ?? uid,
                inputChannels: HAL.channelCount(id, scope: kAudioObjectPropertyScopeInput),
                outputChannels: HAL.channelCount(id, scope: kAudioObjectPropertyScopeOutput),
                sampleRate: HAL.value(id, kAudioDevicePropertyNominalSampleRate, default: Float64(0)) ?? 0,
                transport: transportName(HAL.value(id, kAudioDevicePropertyTransportType, default: UInt32(0)) ?? 0),
                isDefaultInput: id == defaultInput,
                isDefaultOutput: id == defaultOutput
            )
        }
    }

    public static func device(uid: String) -> AudioDeviceInfo? { all().first { $0.uid == uid } }

    /// Calls `handler` on `queue` whenever a device is added or removed. Returns a token; call it to stop listening.
    public static func observeChanges(queue: DispatchQueue, handler: @escaping () -> Void) -> () -> Void {
        var address = HAL.address(kAudioHardwarePropertyDevices)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(system, &address, queue, block)
        return {
            var address = HAL.address(kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(system, &address, queue, block)
        }
    }

    private static func transportName(_ type: UInt32) -> String {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: return "builtin"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "bluetooth"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        default: return "other"
        }
    }
}

/// The same device must never be both where translated speech is written and where anything is captured or
/// monitored, or the call would hear itself. Returns a human-readable reason, or nil when the route is safe.
public func unsafeRouteReason(micUid: String, headphonesUid: String, virtualMicUid: String?) -> String? {
    if let virtualMicUid {
        if virtualMicUid == micUid { return "The virtual microphone cannot also be the capture microphone." }
        if virtualMicUid == headphonesUid {
            return "Incoming audio cannot be played into the virtual microphone — the call would hear it."
        }
    }
    return nil
}
