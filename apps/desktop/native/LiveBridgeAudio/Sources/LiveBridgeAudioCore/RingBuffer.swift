import CAtomicsShim
import Foundation

/// Bounded single-producer / single-consumer ring of Float32 samples.
///
/// `write` may be called from exactly one thread and `read` from exactly one other (the real-time IO thread).
/// Neither side locks, allocates or blocks. `flush` is called by the producer side and takes effect on the
/// consumer's next read, which is how panic-stop empties a playback queue without touching the IO thread.
public final class RingBuffer: @unchecked Sendable {
    public let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    /// Monotonic sample positions; the buffer index is `position % capacity`.
    private let writePosition: UnsafeMutablePointer<Int64>
    private let readPosition: UnsafeMutablePointer<Int64>
    private let flushPosition: UnsafeMutablePointer<Int64>

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
        writePosition = .allocate(capacity: 1)
        readPosition = .allocate(capacity: 1)
        flushPosition = .allocate(capacity: 1)
        writePosition.initialize(to: 0)
        readPosition.initialize(to: 0)
        flushPosition.initialize(to: 0)
    }

    deinit {
        storage.deallocate()
        writePosition.deallocate()
        readPosition.deallocate()
        flushPosition.deallocate()
    }

    /// Total samples ever written. Producer side.
    public var written: Int64 { lb_atomic_load(writePosition) }

    /// Total samples ever consumed (read or flushed past). Safe from any thread.
    public var consumed: Int64 { max(lb_atomic_load(readPosition), lb_atomic_load(flushPosition)) }

    public var availableToRead: Int { Int(max(0, lb_atomic_load(writePosition) - consumed)) }

    /// Producer. Copies as many samples as fit and returns that count; the rest are the caller's overflow.
    @discardableResult
    public func write(_ source: UnsafePointer<Float>, count: Int) -> Int {
        let write = lb_atomic_load(writePosition)
        let free = capacity - Int(write - consumed)
        let n = min(count, max(0, free))
        guard n > 0 else { return 0 }
        let start = Int(write % Int64(capacity))
        let first = min(n, capacity - start)
        (storage + start).update(from: source, count: first)
        if n > first { storage.update(from: source + first, count: n - first) }
        lb_atomic_store(writePosition, write + Int64(n))
        return n
    }

    /// Consumer (real-time safe). Copies up to `count` samples and returns how many were available.
    @discardableResult
    public func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        var read = lb_atomic_load(readPosition)
        let flush = lb_atomic_load(flushPosition)
        if flush > read { read = flush }
        let available = Int(lb_atomic_load(writePosition) - read)
        let n = min(count, max(0, available))
        if n > 0 {
            let start = Int(read % Int64(capacity))
            let first = min(n, capacity - start)
            destination.update(from: storage + start, count: first)
            if n > first { (destination + first).update(from: storage, count: n - first) }
        }
        lb_atomic_store(readPosition, read + Int64(n))
        return n
    }

    /// Producer. Discards everything written so far; the consumer skips it on its next read.
    public func flush() {
        lb_atomic_store(flushPosition, lb_atomic_load(writePosition))
    }
}

/// A flag or counter shared with the real-time IO thread.
public final class AtomicValue: @unchecked Sendable {
    private let pointer: UnsafeMutablePointer<Int64>
    public init(_ value: Int64 = 0) {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: value)
    }
    deinit { pointer.deallocate() }
    public var value: Int64 {
        get { lb_atomic_load(pointer) }
        set { lb_atomic_store(pointer, newValue) }
    }
    public var flag: Bool {
        get { value != 0 }
        set { value = newValue ? 1 : 0 }
    }
    @discardableResult public func add(_ delta: Int64) -> Int64 { lb_atomic_add(pointer, delta) }
}
