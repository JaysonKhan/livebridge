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
  private var events: FlutterEventSink?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    FlutterMethodChannel(name: "livebridge/control", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    FlutterEventChannel(name: "livebridge/events", binaryMessenger: messenger).setStreamHandler(self)
    engine.onEvent = { [weak self] event in
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
      Settings.queue.async {
        Settings.save(arguments)
        DispatchQueue.main.async { result(nil) }
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

/// Last-used configuration. The gateway access token lives in the login Keychain; everything else (device UIDs,
/// language, mode, URL) is in UserDefaults. No captions, audio or transcripts are ever stored.
private enum Settings {
  static let queue = DispatchQueue(label: "livebridge.settings", qos: .userInitiated)
  /// Set LIVEBRIDGE_EPHEMERAL_SETTINGS=1 to keep nothing between launches (automated tests must not touch the
  /// user's Keychain or preferences).
  private static let ephemeral = ProcessInfo.processInfo.environment["LIVEBRIDGE_EPHEMERAL_SETTINGS"] != nil
  private static let defaultsKey = "livebridge.settings"
  private static let tokenKey = "accessToken"
  private static let keychainQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.jaysonkhan.livebridge",
    kSecAttrAccount as String: "gateway-access-token",
  ]

  static func load() -> [String: Any] {
    if ephemeral { return [:] }
    var settings = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
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

  static func save(_ values: [String: Any]) {
    if ephemeral { return }
    var settings = values.filter { !($0.value is NSNull) }
    if let token = settings.removeValue(forKey: tokenKey) as? String {
      SecItemDelete(keychainQuery as CFDictionary)
      if !token.isEmpty {
        var item = keychainQuery
        item[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(item as CFDictionary, nil)
      }
    }
    // Process ids are only meaningful while those processes run; do not restore them into a later launch.
    settings.removeValue(forKey: "sourcePids")
    UserDefaults.standard.set(settings, forKey: defaultsKey)
  }
}
