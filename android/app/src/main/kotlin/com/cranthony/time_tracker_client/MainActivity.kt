package com.cranthony.time_tracker_client

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var oauthChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        oauthChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "time_tracker/oauth")
    }

    // The browser's sign-in redirect (com.cranthony.timetracker://oauth/callback?...)
    // arrives here; see the intent filter in AndroidManifest.xml. The Dart
    // side (AndroidRedirectReceiver) finishes the sign-in with it.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uri = intent.data ?: return
        if (uri.scheme == "com.cranthony.timetracker") {
            oauthChannel?.invokeMethod("redirect", uri.toString())
        }
    }
}
