import Foundation

/// Local usage log for judging speed and quality over time.
///
/// It records **numbers only**: timings, counts, error codes, text lengths and the owner's thumbs-up / thumbs-down.
/// Transcript and translation text never reach the file, and the file never leaves this Mac. One JSON object per
/// line (`type`: `session_start`, `turn`, `e2e`, `empty_turn`, `error`, `reconnect`, `rating`, `session_end`).
///
/// Feed it the same event dictionaries the engine emits (docs/bridge-contract.md); it derives the records itself.
public final class AnalyticsLog: @unchecked Sendable {
    public let fileURL: URL

    private struct PendingTurn {
        var sourceChars: Int?
        var translationChars: Int?
        var e2eMs: Int?
    }

    private static let maxBytes = 20 * 1024 * 1024
    private static let timingFields = ["e2eMs", "sttCommitMs", "translateFirstMs", "translateTotalMs", "ttsFirstAudioMs"]
    private static let turnFields = timingFields + ["ttsTotalMs", "audioMs"]

    private let queue = DispatchQueue(label: "livebridge.analytics")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private var enabled = true
    /// Numbered per install, across app launches and "Clear log": the collector merges a turn's records by it.
    private var session = 0
    private var savedSession = 0
    private var sessionOpen = false
    private var sessionIsMock = false
    private var sessionStartedAt = Date()
    private var sessionTurns = 0
    private var lastState = "idle"
    private var pending: [String: PendingTurn] = [:]
    /// Turns already written whose end-to-end time had not been observed yet.
    private var awaitingE2E: Set<String> = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
        queue.async {
            if let saved = (try? String(contentsOf: self.counterURL, encoding: .utf8)).flatMap({ Int($0) }) {
                self.session = saved
            } else {
                // No counter yet (a log written by an older build): continue after the highest number in it.
                let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                self.session = text.split(separator: "\n").lazy
                    .compactMap { ((try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any])?["session"] as? Int }
                    .max() ?? 0
            }
            self.savedSession = self.session
        }
    }

    /// Survives "Clear log", so a session number is never reused by this install.
    private var counterURL: URL { fileURL.deletingPathExtension().appendingPathExtension("session") }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LiveBridge/analytics.jsonl")
    }

    public var isEnabled: Bool {
        get { queue.sync { enabled } }
        set { queue.async { self.enabled = newValue } }
    }

    /// Takes one engine event. Safe to call from any thread; never blocks the caller.
    public func record(event: [String: Any]) {
        queue.async { self.handle(event) }
    }

    public func rate(direction: String, turnId: Int, rating: String) {
        guard ["good", "bad", "none"].contains(rating) else { return }
        queue.async { self.write(["type": "rating", "direction": direction, "turnId": turnId, "rating": rating]) }
    }

    public func clear() {
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: Deriving records from engine events

    private func handle(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }
        let direction = event["direction"] as? String ?? ""
        let key = "\(direction)#\(event["turnId"] as? Int ?? 0)"

        switch type {
        case "state":
            let state = event["state"] as? String ?? "idle"
            defer { lastState = state }
            if state == "connecting", lastState == "idle" {
                session += 1
                sessionStartedAt = Date()
                sessionTurns = 0
            }
            if state == "ready" || state == "active", !sessionOpen {
                sessionOpen = true
                sessionIsMock = event["mock"] as? Bool ?? false
                var record: [String: Any] = ["type": "session_start"]
                for field in ["mode", "targetLang", "outCommit"] { if let value = event[field] as? String { record[field] = value } }
                write(record)
            }
            if state == "degraded", lastState != "degraded" { write(["type": "reconnect"]) }
            if state == "idle", sessionOpen {
                write([
                    "type": "session_end", "turns": sessionTurns,
                    "durationSec": Int(Date().timeIntervalSince(sessionStartedAt)),
                ])
                sessionOpen = false
                pending.removeAll()
                awaitingE2E.removeAll()
            }
        case "caption":
            // Only the length of the text is kept — never the text.
            let length = (event["text"] as? String ?? "").count
            switch event["kind"] as? String {
            case "final": pending[key, default: PendingTurn()].sourceChars = length
            case "translationFinal": pending[key, default: PendingTurn()].translationChars = length
            case "partial" where length == 0: write(["type": "empty_turn", "direction": direction])
            default: break
            }
        case "metrics":
            if event["translateTotalMs"] != nil {
                // The gateway's stage timings arrive once per translated turn.
                var record: [String: Any] = ["type": "turn", "direction": direction, "turnId": event["turnId"] as? Int ?? 0]
                for field in Self.turnFields { if let value = event[field] as? Int { record[field] = value } }
                if let model = event["model"] as? String { record["model"] = model }
                let turn = pending.removeValue(forKey: key)
                if let chars = turn?.sourceChars { record["sourceChars"] = chars }
                if let chars = turn?.translationChars { record["translationChars"] = chars }
                if record["e2eMs"] == nil, let e2e = turn?.e2eMs { record["e2eMs"] = e2e }
                if record["e2eMs"] == nil { awaitingE2E.insert(key) }
                sessionTurns += 1
                write(record)
            } else if let e2e = event["e2eMs"] as? Int {
                // The client's own observation: push-to-talk release -> first audible translated sample.
                if awaitingE2E.remove(key) != nil {
                    write(["type": "e2e", "direction": direction, "turnId": event["turnId"] as? Int ?? 0, "e2eMs": e2e])
                } else {
                    pending[key, default: PendingTurn()].e2eMs = e2e
                }
            }
        case "error":
            var record: [String: Any] = ["type": "error", "code": event["code"] as? String ?? "error", "fatal": event["fatal"] as? Bool ?? false]
            if !direction.isEmpty { record["direction"] = direction }
            write(record)
        default:
            break
        }
    }

    private func write(_ record: [String: Any]) {
        guard enabled else { return }
        var record = record
        record["t"] = formatter.string(from: Date())
        record["session"] = session
        record["mock"] = sessionIsMock
        guard let json = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if session > savedSession {
            try? String(session).write(to: counterURL, atomically: true, encoding: .utf8)
            savedSession = session
        }
        if let size = (try? manager.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > Self.maxBytes {
            // Bounded on disk: keep one previous file, start a new one.
            let old = fileURL.deletingPathExtension().appendingPathExtension("old.jsonl")
            try? manager.removeItem(at: old)
            try? manager.moveItem(at: fileURL, to: old)
        }
        if !manager.fileExists(atPath: fileURL.path) { manager.createFile(atPath: fileURL.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: json + Data("\n".utf8))
    }

    // MARK: Summary

    /// Aggregates the log for the analytics panel (shape: docs/bridge-contract.md). Sessions against fake providers
    /// are left out of every figure.
    public func summary() -> [String: Any] {
        queue.sync {
            let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let records: [[String: Any]] = text.split(separator: "\n").compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }
            let real = records.filter { ($0["mock"] as? Bool) != true }
            func count(_ type: String) -> Int { real.filter { $0["type"] as? String == type }.count }

            var samples: [String: [Int]] = [:]
            var errors: [String: Int] = [:]
            var ratings: [String: String] = [:]
            for record in real {
                switch record["type"] as? String {
                case "turn", "e2e":
                    for field in Self.timingFields { if let value = record[field] as? Int { samples[field, default: []].append(value) } }
                case "error":
                    errors[record["code"] as? String ?? "error", default: 0] += 1
                case "rating":
                    // The latest judgement of a turn wins; "none" withdraws it.
                    let turn = "\(record["session"] ?? 0)#\(record["direction"] ?? "")#\(record["turnId"] ?? 0)"
                    ratings[turn] = record["rating"] as? String
                default: break
                }
            }

            var result: [String: Any] = [
                "enabled": enabled,
                "path": fileURL.path,
                "fileSizeBytes": ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int) ?? 0,
                "sessions": count("session_start"),
                "turns": count("turn"),
                "errors": errors,
                "reconnects": count("reconnect"),
                "emptyTurns": count("empty_turn"),
                "ratedGood": ratings.values.filter { $0 == "good" }.count,
                "ratedBad": ratings.values.filter { $0 == "bad" }.count,
            ]
            if let first = records.first?["t"] as? String { result["firstAt"] = first }
            if let last = records.last?["t"] as? String { result["lastAt"] = last }
            for (field, values) in samples {
                let sorted = values.sorted()
                func percentile(_ p: Double) -> Int { sorted[min(sorted.count - 1, max(0, Int((p * Double(sorted.count)).rounded(.up)) - 1))] }
                result[field] = ["count": sorted.count, "p50": percentile(0.5), "p95": percentile(0.95), "max": sorted[sorted.count - 1]]
            }
            return result
        }
    }
}
