import 'dart:io';

import 'redirect_receiver.dart';

// The web build imports platform_receiver_web.dart instead (see main.dart).

String get platformName => Platform.operatingSystem;

RedirectReceiver platformRedirectReceiver() =>
    Platform.isAndroid ? AndroidRedirectReceiver() : LoopbackRedirectReceiver();
