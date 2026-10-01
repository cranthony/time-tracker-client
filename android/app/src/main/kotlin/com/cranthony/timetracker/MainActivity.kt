package com.cranthony.timetracker

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var oauthChannel: MethodChannel? = null
    private var addNoteChannel: MethodChannel? = null

    /**
     * When the home screen "+" launched the app from scratch: the Dart side
     * isn't listening yet, so it collects this with "takeLaunchRequest".
     */
    private var launchAddNoteAt: Long? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Not when re-created: that's the same launch, already handled.
        if (savedInstanceState == null && isAddNote(intent)) {
            Log.d(TAG, "onCreate: add note")
            launchAddNoteAt = System.currentTimeMillis()
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        oauthChannel = MethodChannel(messenger, "time_tracker/oauth")
        addNoteChannel = MethodChannel(messenger, AddNoteWidget.CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "takeLaunchRequest") {
                    result.success(launchAddNoteAt)
                    launchAddNoteAt = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // The home screen "+" tapped while the app was already running.
        if (isAddNote(intent)) {
            Log.d(TAG, "onNewIntent: add note")
            addNoteChannel?.invokeMethod("addNote", System.currentTimeMillis())
            return
        }
        // The browser's sign-in redirect (com.cranthony.timetracker://oauth/callback?...)
        // arrives here; see the intent filter in AndroidManifest.xml. The Dart
        // side (AndroidRedirectReceiver) finishes the sign-in with it.
        val uri = intent.data ?: return
        if (uri.scheme == "com.cranthony.timetracker") {
            oauthChannel?.invokeMethod("redirect", uri.toString())
        }
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "onResume")
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        Log.d(TAG, "onWindowFocusChanged: $hasFocus")
    }

    /** Ignores relaunching from Recents, which replays the original intent. */
    private fun isAddNote(intent: Intent?): Boolean =
        intent?.action == AddNoteWidget.ACTION_ADD_NOTE &&
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0

    private companion object {
        // adb logcat -s TimeTracker flutter
        const val TAG = "TimeTracker"
    }
}
