import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The desktop system the app runs on. It decides the setup wording: BlackHole and the macOS texts on macOS,
/// VB-CABLE and the Windows privacy setting on Windows.
enum HostPlatform { macos, windows }

/// The running system. Widget tests override it to check the Windows wording on any machine.
final hostPlatformProvider = Provider<HostPlatform>(
  (ref) => defaultTargetPlatform == TargetPlatform.windows ? HostPlatform.windows : HostPlatform.macos,
);
