import Foundation

/// Binary audio frame v1 — must stay byte-identical to `packages/protocol/src/frame.ts`.
/// Both codecs are tested against `packages/protocol/fixtures/frames.json`.
public struct AudioFrame: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case capture = 1, synthesized = 2 }
    public enum Direction: UInt8, Sendable {
        case out = 0, `in` = 1
        public var name: String { self == .out ? "out" : "in" }
        public init?(name: String) {
            switch name {
            case "out": self = .out
            case "in": self = .in
            default: return nil
            }
        }
    }

    public static let version: UInt8 = 1
    public static let headerBytes = 28
    public static let maxPayloadBytes = 192_000
    public static let flagEndOfTurn: UInt8 = 0x01

    public var kind: Kind
    public var direction: Direction
    public var flags: UInt8
    public var generation: UInt32
    public var sequence: UInt32
    public var timestampUs: UInt64
    public var turnId: UInt32
    public var payload: Data

    public init(
        kind: Kind, direction: Direction, flags: UInt8 = 0, generation: UInt32, sequence: UInt32,
        timestampUs: UInt64, turnId: UInt32 = 0, payload: Data
    ) {
        self.kind = kind
        self.direction = direction
        self.flags = flags
        self.generation = generation
        self.sequence = sequence
        self.timestampUs = timestampUs
        self.turnId = turnId
        self.payload = payload
    }

    public var isEndOfTurn: Bool { flags & Self.flagEndOfTurn != 0 }
}

public enum FrameError: String, Error, Equatable {
    case tooShort = "too_short"
    case badVersion = "bad_version"
    case badKind = "bad_kind"
    case badDirection = "bad_direction"
    case badFlags = "bad_flags"
    case lengthMismatch = "length_mismatch"
    case payloadTooLarge = "payload_too_large"
    case oddPayload = "odd_payload"
}

public enum FrameCodec {
    public static func encode(_ frame: AudioFrame) throws -> Data {
        guard frame.payload.count <= AudioFrame.maxPayloadBytes else { throw FrameError.payloadTooLarge }
        guard frame.payload.count % 2 == 0 else { throw FrameError.oddPayload }
        guard frame.flags & ~AudioFrame.flagEndOfTurn == 0 else { throw FrameError.badFlags }
        var data = Data(capacity: AudioFrame.headerBytes + frame.payload.count)
        data.append(AudioFrame.version)
        data.append(frame.kind.rawValue)
        data.append(frame.direction.rawValue)
        data.append(frame.flags)
        appendBigEndian(frame.generation, to: &data)
        appendBigEndian(frame.sequence, to: &data)
        appendBigEndian(frame.timestampUs, to: &data)
        appendBigEndian(frame.turnId, to: &data)
        appendBigEndian(UInt32(frame.payload.count), to: &data)
        data.append(frame.payload)
        return data
    }

    public static func decode(_ data: Data) throws -> AudioFrame {
        guard data.count >= AudioFrame.headerBytes else { throw FrameError.tooShort }
        let bytes = [UInt8](data.prefix(AudioFrame.headerBytes))
        guard bytes[0] == AudioFrame.version else { throw FrameError.badVersion }
        guard let kind = AudioFrame.Kind(rawValue: bytes[1]) else { throw FrameError.badKind }
        guard let direction = AudioFrame.Direction(rawValue: bytes[2]) else { throw FrameError.badDirection }
        guard bytes[3] & ~AudioFrame.flagEndOfTurn == 0 else { throw FrameError.badFlags }
        let size = Int(readBigEndian(bytes, 24, as: UInt32.self))
        guard size <= AudioFrame.maxPayloadBytes else { throw FrameError.payloadTooLarge }
        guard size == data.count - AudioFrame.headerBytes else { throw FrameError.lengthMismatch }
        guard size % 2 == 0 else { throw FrameError.oddPayload }
        return AudioFrame(
            kind: kind,
            direction: direction,
            flags: bytes[3],
            generation: readBigEndian(bytes, 4, as: UInt32.self),
            sequence: readBigEndian(bytes, 8, as: UInt32.self),
            timestampUs: readBigEndian(bytes, 12, as: UInt64.self),
            turnId: readBigEndian(bytes, 20, as: UInt32.self),
            payload: Data(data.suffix(size))
        )
    }

    private static func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    private static func readBigEndian<T: FixedWidthInteger>(_ bytes: [UInt8], _ offset: Int, as: T.Type) -> T {
        var value: T = 0
        for i in 0..<MemoryLayout<T>.size { value = (value << 8) | T(bytes[offset + i]) }
        return value
    }
}
