import Foundation

/// The single client connection to the gateway: one authenticated WebSocket carrying JSON control messages and
/// binary audio frames for both directions. All callbacks arrive on the queue given at init.
final class GatewayTransport: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    var onMessage: (([String: Any]) -> Void)?
    var onFrame: ((Data) -> Void)?
    /// The connection ended without `close()` being called.
    var onClosed: ((String) -> Void)?

    /// Capture frames allowed to wait for the network: 25 × 20 ms = 500 ms. Beyond that new frames are dropped.
    private static let maxPendingFrames = 25

    private let queue: DispatchQueue
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var opening: ((Result<Void, AudioEngineError>) -> Void)?
    private var pendingFrames = 0
    private var closedByUs = false
    private var pingTimer: DispatchSourceTimer?

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    /// Exchanges the long-lived access token for a short-lived session token, then opens the realtime socket.
    func connect(baseURL: URL, accessToken: String, completion: @escaping (Result<Void, AudioEngineError>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/sessions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self, !self.closedByUs else { return }
            guard let http = response as? HTTPURLResponse else {
                return completion(.failure(AudioEngineError("gateway_unreachable", error?.localizedDescription ?? "no response from the gateway")))
            }
            guard http.statusCode == 201, let data,
                let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let token = body["token"] as? String
            else {
                let reasons = [401: ("unauthorized", "the gateway rejected the access token"), 429: ("session_limit", "the gateway already has an active session")]
                let (code, message) = reasons[http.statusCode] ?? ("gateway_error", "gateway answered HTTP \(http.statusCode)")
                return completion(.failure(AudioEngineError(code, message)))
            }
            guard var components = URLComponents(url: baseURL.appendingPathComponent("v1/realtime"), resolvingAgainstBaseURL: false)
            else { return completion(.failure(AudioEngineError("gateway_error", "invalid gateway URL"))) }
            components.scheme = components.scheme == "https" ? "wss" : "ws"
            var socketRequest = URLRequest(url: components.url!)
            socketRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let task = self.session.webSocketTask(with: socketRequest)
            task.maximumMessageSize = 512 * 1024
            self.task = task
            self.opening = completion
            task.resume()
            self.receive(on: task)
        }.resume()
    }

    func send(_ message: [String: Any]) {
        var message = message
        message["v"] = 1
        guard let task, let data = try? JSONSerialization.data(withJSONObject: message),
            let text = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(text)) { _ in }
    }

    /// Returns false when the frame was dropped because the network is not keeping up.
    func send(frame: Data) -> Bool {
        guard let task else { return false }
        guard pendingFrames < Self.maxPendingFrames else { return false }
        pendingFrames += 1
        task.send(.data(frame)) { [weak self] _ in self?.pendingFrames -= 1 }
        return true
    }

    func close() {
        closedByUs = true
        pingTimer?.cancel()
        pingTimer = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session.invalidateAndCancel()
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.task === task, case .success(let message) = result else { return }
            switch message {
            case .data(let data): self.onFrame?(data)
            case .string(let text):
                if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                    self.onMessage?(object)
                }
            @unknown default: break
            }
            self.receive(on: task)
        }
    }

    private func ended(_ reason: String) {
        guard !closedByUs, task != nil else { return }
        task = nil
        pingTimer?.cancel()
        pingTimer = nil
        if let opening {
            self.opening = nil
            opening(.failure(AudioEngineError("gateway_unreachable", reason)))
        } else {
            onClosed?(reason)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard webSocketTask === task, let opening else { return }
        self.opening = nil
        // A dead peer is otherwise only noticed when a send fails; ping so a silent drop surfaces within seconds.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.task?.sendPing { error in
                if let error { self?.ended("ping failed: \(error.localizedDescription)") }
            }
        }
        timer.resume()
        pingTimer = timer
        opening(.success(()))
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if webSocketTask === task { ended("the gateway closed the connection (\(closeCode.rawValue))") }
    }

    func urlSession(_ session: URLSession, task finished: URLSessionTask, didCompleteWithError error: Error?) {
        if finished === task { ended(error?.localizedDescription ?? "connection ended") }
    }
}
