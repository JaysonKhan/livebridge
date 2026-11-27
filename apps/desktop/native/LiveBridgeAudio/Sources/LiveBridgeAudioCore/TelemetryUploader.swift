import Foundation

/// Opt-in upload of the numbers-only analytics log to the developer's collector, and feedback submission.
/// Wire contract: docs/telemetry-api.md. Nothing is sent unless `isEnabled` is true (default false); feedback is
/// sent only when the user submits it.
///
/// It reads the same file `AnalyticsLog` writes, so it can only ever send what that log holds — timings, counts,
/// codes, text lengths, ratings. It remembers how far it has uploaded and resumes there; a failed upload is retried
/// the next time, never queued in memory.
public final class TelemetryUploader: @unchecked Sendable {
    public static let defaultEndpoint = URL(string: "https://jaysonkhan.com/api/services/v1")!
    public static let publicStatsURL = "https://jaysonkhan.com/services/livebridge/"

    public enum FeedbackError: String, Error { case rateLimited = "rate_limited", rejected = "feedback_rejected", failed = "feedback_failed" }

    private static let batchSize = 500
    /// `macOS 26.6.2`: reported with uploads and in `status()`.
    static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
    private let logURL: URL
    private let endpoint: URL
    private let store: UserDefaults
    private let session: URLSession
    private let appVersion: String
    private let queue = DispatchQueue(label: "livebridge.telemetry")
    private var enabled = false
    private var uploading = false
    private var lastError: String?
    /// Interface language reported with uploads (`uz`, `ru`, `tr`, `en`); optional.
    public var uiLanguage: String?

    private enum Key {
        static let installId = "livebridge.telemetry.installId"
        static let offset = "livebridge.telemetry.offset"
        static let lastUploadAt = "livebridge.telemetry.lastUploadAt"
    }

    public init(
        logURL: URL, endpoint: URL = TelemetryUploader.defaultEndpoint, store: UserDefaults = .standard,
        session: URLSession = .shared, appVersion: String
    ) {
        self.logURL = logURL
        self.endpoint = endpoint
        self.store = store
        self.session = session
        self.appVersion = appVersion
    }

    /// Switching on creates the random install id (once); switching off only stops uploading.
    public var isEnabled: Bool {
        get { queue.sync { enabled } }
        set {
            queue.sync {
                enabled = newValue
                if newValue, store.string(forKey: Key.installId) == nil { store.set(UUID().uuidString.lowercased(), forKey: Key.installId) }
            }
        }
    }

    /// Sharing on by default, when the user never chose: an install that never shared starts at the current end of the
    /// log, so nothing written before this moment is sent. An install that shared before keeps its position.
    public func enableFromNow() {
        queue.sync {
            if store.string(forKey: Key.installId) == nil {
                let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
                store.set(size ?? 0, forKey: Key.offset)
            }
        }
        isEnabled = true
    }

    public func status() -> [String: Any] {
        queue.sync {
            var status: [String: Any] = [
                "enabled": enabled, "endpoint": endpoint.absoluteString, "pendingRecords": pending().records.count,
                "appVersion": appVersion, "osVersion": Self.osVersion,
            ]
            if let id = store.string(forKey: Key.installId) { status["installId"] = id }
            if let at = store.string(forKey: Key.lastUploadAt) { status["lastUploadAt"] = at }
            if let lastError { status["lastError"] = lastError }
            return status
        }
    }

    /// Uploads whatever the log gained since the last successful upload. `completion` gets the number of records
    /// the server accepted (0 when disabled, nothing new, or the upload failed).
    public func uploadPending(completion: ((Int) -> Void)? = nil) {
        queue.async {
            guard self.enabled, !self.uploading, let installId = self.store.string(forKey: Key.installId) else {
                completion?(0)
                return
            }
            self.uploading = true
            self.uploadNext(installId: installId, total: 0) { total in
                self.uploading = false
                completion?(total)
            }
        }
    }

    public func sendFeedback(message: String, email: String?, rating: Int?, completion: @escaping (Result<Void, FeedbackError>) -> Void) {
        var body: [String: Any] = ["app": "livebridge", "app_version": appVersion, "message": message]
        if let uiLanguage { body["ui_language"] = uiLanguage }
        if let email, !email.isEmpty { body["email"] = email }
        if let rating { body["rating"] = rating }
        // The install id links feedback to statistics only when the user chose to share statistics.
        if isEnabled, let id = store.string(forKey: Key.installId) { body["install_id"] = id }
        post("feedback/", body) { status in
            switch status {
            case 201, 200: completion(.success(()))
            case 429: completion(.failure(.rateLimited))
            case 400, 413: completion(.failure(.rejected))
            default: completion(.failure(.failed))
            }
        }
    }

    // MARK: Upload

    /// Records after the stored offset, and where each ends in the file. Lines from mock sessions are skipped but
    /// still advance the offset. Only complete lines are read.
    private func pending() -> (records: [[String: Any]], ends: [Int], scannedTo: Int) {
        guard let data = try? Data(contentsOf: logURL) else { return ([], [], 0) }
        var offset = store.integer(forKey: Key.offset)
        // The log was cleared or rotated: start again from its beginning.
        if offset > data.count { offset = 0 }
        var records: [[String: Any]] = []
        var ends: [Int] = []
        var lineStart = offset
        var scannedTo = offset
        for index in offset..<data.count where data[index] == 0x0A {
            let line = data.subdata(in: lineStart..<index)
            lineStart = index + 1
            scannedTo = lineStart
            guard var record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], record["mock"] as? Bool != true else { continue }
            record.removeValue(forKey: "mock")
            records.append(record)
            ends.append(lineStart)
        }
        return (records, ends, scannedTo)
    }

    private func uploadNext(installId: String, total: Int, completion: @escaping (Int) -> Void) {
        let (records, ends, scannedTo) = pending()
        guard !records.isEmpty else {
            // Nothing uploadable left; step over skipped (mock) lines so they are not rescanned.
            store.set(scannedTo, forKey: Key.offset)
            return completion(total)
        }
        let count = min(Self.batchSize, records.count)
        var body: [String: Any] = [
            "app": "livebridge", "schema": 1, "install_id": installId, "app_version": appVersion,
            "os_version": Self.osVersion,
            "records": Array(records.prefix(count)),
        ]
        if let uiLanguage { body["ui_language"] = uiLanguage }
        post("telemetry/", body) { status in
            self.queue.async {
                switch status {
                case 200...299:
                    self.store.set(ends[count - 1], forKey: Key.offset)
                    self.store.set(ISO8601DateFormatter().string(from: Date()), forKey: Key.lastUploadAt)
                    self.lastError = nil
                    self.uploadNext(installId: installId, total: total + count, completion: completion)
                case 400, 413:
                    // The server will never accept this batch; skip it rather than block everything behind it.
                    self.store.set(ends[count - 1], forKey: Key.offset)
                    self.lastError = "the server rejected a batch (HTTP \(status))"
                    self.uploadNext(installId: installId, total: total, completion: completion)
                default:
                    // Rate limited, server error or offline: keep the position and try again next time.
                    self.lastError = status == 0 ? "could not reach the server" : "upload failed (HTTP \(status))"
                    completion(total)
                }
            }
        }
    }

    /// POSTs JSON and reports the HTTP status (0 = no response).
    private func post(_ path: String, _ body: [String: Any], completion: @escaping (Int) -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return completion(0) }
        // Built as a string so the trailing slash the server requires is kept exactly.
        guard let url = URL(string: endpoint.absoluteString + "/" + path) else { return completion(0) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 15
        // No cookies or stored credentials travel with telemetry.
        request.httpShouldHandleCookies = false
        session.dataTask(with: request) { _, response, _ in
            completion((response as? HTTPURLResponse)?.statusCode ?? 0)
        }.resume()
    }
}
