import AVFoundation
import Cocoa
import FlutterMacOS
import LiveBridgeAudioCore
import Security

class MainFlutterWindow: NSWindow {
  private var bridge: LiveBridgeChannels?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.minSize = NSSize(width: 980, height: 680)
    self.setContentSize(NSSize(width: 1240, height: 800))
    self.center()
    self.title = "LiveBridge"

    RegisterGeneratedPlugins(registry: flutterViewController)
    bridge = LiveBridgeChannels(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// The Flutter side of docs/bridge-contract.md. Low-rate commands in, captions / state / throttled meters out;
/// audio never crosses this boundary.
final class LiveBridgeChannels: NSObject, FlutterStreamHandler {
  private let engine = Engine()
  private let analytics = AnalyticsLog(fileURL: AnalyticsLog.defaultURL())
  private var events: FlutterEventSink?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    FlutterMethodChannel(name: "livebridge/control", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    FlutterEventChannel(name: "livebridge/events", binaryMessenger: messenger).setStreamHandler(self)
    // Automated test runs (ephemeral settings) must not write into the user's analytics either.
    analytics.isEnabled = !Settings.ephemeral && (Settings.preferences()["analyticsEnabled"] as? Bool ?? true)
    engine.onEvent = { [weak self] event in
      // The analytics log keeps numbers only (timings, counts, codes); caption text is reduced to its length.
      self?.analytics.record(event: event)
      DispatchQueue.main.async { self?.events?(event) }
    }
    // Quitting mid-session must leave the virtual microphone silent, not half-way through a sentence.
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [engine] _ in engine.panic() }
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    events = eventSink
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "listDevices":
      result(AudioDevices.all().map(\.dictionary))
    case "listAudioProcesses":
      result(AudioProcesses.all().map(\.dictionary))
    case "loadSettings":
      // Keychain calls can wait on a system prompt (e.g. after the app was rebuilt with a new signature), so they
      // never run on the UI thread.
      Settings.queue.async {
        let settings = Settings.load()
        DispatchQueue.main.async { result(settings) }
      }
    case "saveSettings":
      if let enabled = arguments["analyticsEnabled"] as? Bool { analytics.isEnabled = enabled && !Settings.ephemeral }
      Settings.queue.async {
        Settings.save(arguments)
        DispatchQueue.main.async { result(nil) }
      }
    case "saveTextFile":
      guard let content = arguments["content"] as? String else { return result(Self.badArguments) }
      save(suggestedName: arguments["suggestedName"] as? String ?? "livebridge.md", result) { url in
        try content.write(to: url, atomically: true, encoding: .utf8)
      }
    case "rateTurn":
      guard let direction = arguments["direction"] as? String, let turn = arguments["turnId"] as? Int,
        let rating = arguments["rating"] as? String
      else { return result(Self.badArguments) }
      analytics.rate(direction: direction, turnId: turn, rating: rating)
      result(nil)
    case "analyticsSummary":
      Settings.queue.async { [analytics] in
        let summary = analytics.summary()
        DispatchQueue.main.async { result(summary) }
      }
    case "analyticsExport":
      let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
      save(suggestedName: "livebridge-analytics-\(day).jsonl", result) { [analytics] url in
        let log = (try? Data(contentsOf: analytics.fileURL)) ?? Data()
        try log.write(to: url, options: .atomic)
      }
    case "analyticsClear":
      analytics.clear()
      result(nil)
    case "microphonePermission":
      result(Self.microphonePermission())
    case "requestMicrophonePermission":
      AVCaptureDevice.requestAccess(for: .audio) { granted in DispatchQueue.main.async { result(granted) } }
    case "startMeters":
      engine.startMeters(micUid: arguments["micUid"] as? String, sourcePids: Self.pids(arguments["sourcePids"]))
      result(nil)
    case "stopMeters":
      engine.stopMeters()
      result(nil)
    case "testTone":
      guard let uid = arguments["uid"] as? String else { return result(Self.badArguments) }
      engine.testTone(uid: uid)
      result(nil)
    case "start":
      guard let config = EngineConfig(dictionary: arguments) else { return result(Self.badArguments) }
      engine.start(config)
      result(nil)
    case "stop":
      engine.stop()
      result(nil)
    case "pttDown":
      engine.pttDown()
      result(nil)
    case "pttUp":
      engine.pttUp()
      result(nil)
    case "setOutgoingMuted":
      engine.setOutgoingMuted(arguments["muted"] as? Bool ?? false)
      result(nil)
    case "setIncomingAudioMuted":
      engine.setIncomingAudioMuted(arguments["muted"] as? Bool ?? false)
      result(nil)
    case "setBypass":
      engine.setBypass(arguments["enabled"] as? Bool ?? false)
      result(nil)
    case "panic":
      engine.panic()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Shows the system Save dialog and runs `write` with the chosen location. Nothing is written without the user
  /// choosing where: exports are always an explicit action.
  private func save(suggestedName: String, _ result: @escaping FlutterResult, write: @escaping (URL) throws -> Void) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = suggestedName
    panel.canCreateDirectories = true
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return result(nil) }
      do {
        try write(url)
        result(url.path)
      } catch {
        result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  private static let badArguments = FlutterError(code: "bad_arguments", message: "missing or invalid arguments", details: nil)

  private static func pids(_ value: Any?) -> [pid_t] {
    (value as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.int32Value }
  }

  private static func microphonePermission() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return "granted"
    case .denied, .restricted: return "denied"
    default: return "undetermined"
    }
  }
}

/// Last-used configuration and preferences. The gateway access token lives in the login Keychain; everything else
/// (device UIDs, language, mode, URL, interface language, caption preferences) is in UserDefaults. No captions,
/// audio or transcripts are ever stored here.
private enum Settings {
  static let queue = DispatchQueue(label: "livebridge.settings", qos: .userInitiated)
  /// Set LIVEBRIDGE_EPHEMERAL_SETTINGS=1 to keep nothing between launches (automated tests must not touch the
  /// user's Keychain or preferences).
  static let ephemeral = ProcessInfo.processInfo.environment["LIVEBRIDGE_EPHEMERAL_SETTINGS"] != nil
  private static let defaultsKey = "livebridge.settings"
  private static let tokenKey = "accessToken"
  private static let keychainQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.jaysonkhan.livebridge",
    kSecAttrAccount as String: "gateway-access-token",
  ]

  /// Everything except the token — never touches the Keychain, so it is safe on any thread.
  static func preferences() -> [String: Any] {
    ephemeral ? [:] : UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
  }

  static func load() -> [String: Any] {
    if ephemeral { return [:] }
    var settings = preferences()
    var query = keychainQuery
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
      let token = String(data: data, encoding: .utf8)
    {
      settings[tokenKey] = token
    }
    return settings
  }

  /// Merges the given keys into what is stored; a null value removes a key.
  static func save(_ values: [String: Any]) {
    if ephemeral { return }
    var settings = preferences()
    for (key, value) in values where key != tokenKey && key != "sourcePids" {
      // Process ids are only meaningful while those processes run, so they are never stored.
      if value is NSNull { settings.removeValue(forKey: key) } else { settings[key] = value }
    }
    if let token = values[tokenKey] as? String {
      SecItemDelete(keychainQuery as CFDictionary)
      if !token.isEmpty {
        var item = keychainQuery
        item[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(item as CFDictionary, nil)
      }
    }
    UserDefaults.standard.set(settings, forKey: defaultsKey)
  }
}
