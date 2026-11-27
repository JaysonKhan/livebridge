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
    self.title = "JK - LiveBridge"
    // Unified title bar: an empty unified toolbar makes the title area 52 pt tall with the traffic lights centred in
    // it, and the Flutter header (lib/ui/adaptive/platform_header.dart) draws the toolbar row underneath.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.toolbar = NSToolbar(identifier: "LiveBridgeToolbar")
    self.toolbarStyle = .unified
    self.titlebarSeparatorStyle = .none
    // FlutterView is opaque and receives the clicks in the transparent title area, so AppKit never drags the window
    // from there: the header asks for the drag, and for the title bar's double-click action. In full screen the
    // traffic lights are hidden, so the header is told to drop the room it keeps for them.
    let windowChannel = FlutterMethodChannel(
      name: "livebridge/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    let center = NotificationCenter.default
    center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: self, queue: .main) { [weak self] _ in
      // In full screen the empty toolbar is drawn as an opaque band over the header; the header needs no toolbar.
      self?.toolbar?.isVisible = false
      windowChannel.invokeMethod("fullScreen", arguments: true)
    }
    center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: self, queue: .main) { _ in
      windowChannel.invokeMethod("fullScreen", arguments: false)
    }
    center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: self, queue: .main) { [weak self] _ in
      self?.toolbar?.isVisible = true
    }
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent { self.performDrag(with: event) }
        result(nil)
      case "titleBarDoubleClick":
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": self.performMiniaturize(nil)
        case "None": break
        default: self.performZoom(nil)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

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
  /// Upload of the numbers-only log to the developer's collector (docs/telemetry-api.md). On unless the user switched
  /// it off; a saved `false` stays off.
  private let telemetry: TelemetryUploader
  private var events: FlutterEventSink?
  private var sessionRunning = false

  init(messenger: FlutterBinaryMessenger) {
    let preferences = Settings.preferences()
    let info = Bundle.main.infoDictionary
    telemetry = TelemetryUploader(
      logURL: AnalyticsLog.defaultURL(),
      // Forks and tests can point this elsewhere with the `telemetryEndpoint` preference.
      endpoint: (preferences["telemetryEndpoint"] as? String).flatMap(URL.init(string:)) ?? TelemetryUploader.defaultEndpoint,
      appVersion: "\(info?["CFBundleShortVersionString"] as? String ?? "0")+\(info?["CFBundleVersion"] as? String ?? "0")")
    super.init()
    telemetry.uiLanguage = preferences["uiLanguage"] as? String
    // With no saved choice sharing is on, unless the analytics log was switched off; it then starts from now, so the
    // log's earlier records are not sent.
    if Settings.ephemeral {
      telemetry.isEnabled = false
    } else if let saved = preferences["telemetryEnabled"] as? Bool {
      telemetry.isEnabled = saved
    } else if preferences["analyticsEnabled"] as? Bool ?? true {
      telemetry.enableFromNow()
    }
    telemetry.uploadPending()
    FlutterMethodChannel(name: "livebridge/control", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    FlutterEventChannel(name: "livebridge/events", binaryMessenger: messenger).setStreamHandler(self)
    // Automated test runs (ephemeral settings) must not write into the user's analytics either.
    analytics.isEnabled = !Settings.ephemeral && (Settings.preferences()["analyticsEnabled"] as? Bool ?? true)
    engine.onEvent = { [weak self] event in
      // The analytics log keeps numbers only (timings, counts, codes); caption text is reduced to its length.
      self?.analytics.record(event: event)
      DispatchQueue.main.async {
        self?.sessionEnded(ifIdle: event)
        self?.events?(event)
      }
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
      if let language = arguments["uiLanguage"] as? String { telemetry.uiLanguage = language }
      if let enabled = arguments["telemetryEnabled"] as? Bool {
        telemetry.isEnabled = enabled && !Settings.ephemeral
        telemetry.uploadPending()
      }
      Settings.queue.async {
        let failed = Settings.save(arguments)
        DispatchQueue.main.async {
          // Only the item's key is named, never its value.
          result(
            failed.isEmpty
              ? nil
              : FlutterError(code: "settings_failed", message: "could not store: \(failed.sorted().joined(separator: ", "))", details: nil))
        }
      }
    case "languageNames":
      // Language names in the interface language, from the system's own locale data.
      guard let codes = arguments["codes"] as? [String] else { return result(Self.badArguments) }
      let locale = Locale(identifier: arguments["locale"] as? String ?? "en")
      var names: [String: String] = [:]
      for code in codes {
        guard let name = locale.localizedString(forLanguageCode: code), !name.isEmpty else { continue }
        names[code] = name.prefix(1).uppercased(with: locale) + name.dropFirst()
      }
      result(names)
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
    case "telemetryStatus":
      Settings.queue.async { [telemetry] in
        let status = telemetry.status()
        DispatchQueue.main.async { result(status) }
      }
    case "sendFeedback":
      let message = (arguments["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !message.isEmpty, message.count <= 2000 else { return result(Self.badArguments) }
      telemetry.sendFeedback(message: message, email: arguments["email"] as? String, rating: arguments["rating"] as? Int) { outcome in
        DispatchQueue.main.async {
          switch outcome {
          case .success: result(nil)
          case .failure(let error): result(FlutterError(code: error.rawValue, message: "feedback was not sent", details: nil))
          }
        }
      }
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
    case "updateAccessToken":
      guard let token = arguments["accessToken"] as? String, !token.isEmpty else { return result(Self.badArguments) }
      engine.updateAccessToken(token)
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
    case "setOutCommit":
      guard let commit = arguments["commit"] as? String, EngineConfig.outCommits.contains(commit) else {
        return result(Self.badArguments)
      }
      engine.setOutCommit(commit)
      result(nil)
    case "panic":
      engine.panic()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// After a session ends, offer the new numbers to the collector (a no-op unless the user opted in).
  private func sessionEnded(ifIdle event: [String: Any]) {
    guard event["type"] as? String == "state", let state = event["state"] as? String else { return }
    let wasRunning = sessionRunning
    sessionRunning = state != "idle"
    guard wasRunning, !sessionRunning else { return }
    // Give the log a moment to write the session's last record first.
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [telemetry] in telemetry.uploadPending() }
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

/// Last-used configuration and preferences. The secrets (static gateway token, account refresh token, provider keys)
/// live in the login Keychain, one item each; everything else
/// (device UIDs, language, mode, URL, interface language, caption preferences) is in UserDefaults. No captions,
/// audio or transcripts are ever stored here.
private enum Settings {
  static let queue = DispatchQueue(label: "livebridge.settings", qos: .userInitiated)
  /// Set LIVEBRIDGE_EPHEMERAL_SETTINGS=1 to keep nothing between launches (automated tests must not touch the
  /// user's Keychain or preferences).
  static let ephemeral = ProcessInfo.processInfo.environment["LIVEBRIDGE_EPHEMERAL_SETTINGS"] != nil
  private static let defaultsKey = "livebridge.settings"
  /// Settings key -> Keychain account. These keys never reach UserDefaults.
  private static let secretAccounts: [String: String] = [
    "accessToken": "gateway-access-token",
    "accountRefreshToken": "account-refresh-token",
    "elevenlabsApiKey": "elevenlabs-api-key",
    "geminiApiKey": "gemini-api-key",
  ]

  private static func keychainQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.jaysonkhan.livebridge",
      kSecAttrAccount as String: account,
    ]
  }

  /// Everything except the token — never touches the Keychain, so it is safe on any thread.
  static func preferences() -> [String: Any] {
    ephemeral ? [:] : UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
  }

  static func load() -> [String: Any] {
    if ephemeral { return [:] }
    var settings = preferences()
    for (key, account) in secretAccounts {
      var query = keychainQuery(account: account)
      query[kSecReturnData as String] = true
      var item: CFTypeRef?
      if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
        let secret = String(data: data, encoding: .utf8)
      {
        settings[key] = secret
      }
    }
    return settings
  }

  /// Merges the given keys into what is stored; a null value removes a key (a secret's Keychain item included), and
  /// a key that is absent is left alone. Returns the keys of secrets whose Keychain write or delete failed.
  @discardableResult
  static func save(_ values: [String: Any]) -> [String] {
    if ephemeral { return [] }
    var settings = preferences()
    for (key, value) in values where secretAccounts[key] == nil && key != "sourcePids" {
      // Process ids are only meaningful while those processes run, so they are never stored.
      if value is NSNull { settings.removeValue(forKey: key) } else { settings[key] = value }
    }
    var failed: [String] = []
    for (key, account) in secretAccounts {
      guard let value = values[key], value is NSNull || value is String else { continue }
      let query = keychainQuery(account: account)
      let status: OSStatus
      if let secret = value as? String, !secret.isEmpty {
        // Update in place so a failed write never leaves the old value deleted; add only when there is none yet.
        let data = Data(secret.utf8)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecItemNotFound {
          var item = query
          item[kSecValueData as String] = data
          status = SecItemAdd(item as CFDictionary, nil)
        } else {
          status = updated
        }
      } else {
        let deleted = SecItemDelete(query as CFDictionary)
        status = deleted == errSecItemNotFound ? errSecSuccess : deleted
      }
      if status != errSecSuccess { failed.append(key) }
    }
    UserDefaults.standard.set(settings, forKey: defaultsKey)
    return failed
  }
}
