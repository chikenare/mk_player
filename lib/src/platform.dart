import 'package:flutter/foundation.dart';

/// Platform predicates used to tailor controls and fullscreen behaviour.

/// A desktop operating system (macOS / Windows / Linux), excluding web.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Android, excluding web.
bool get isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// iOS, excluding web.
bool get isIOSPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// A mobile operating system (Android / iOS), excluding web.
bool get isMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Desktop OS or web — environments with a pointer and no hardware volume keys.
bool get isDesktopOrWeb => kIsWeb || isDesktopPlatform;
