package com.cranthony.timetracker

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowInsets
import android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
import android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE
import android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_UNSPECIFIED
import android.view.inputmethod.InputMethodManager
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

    /** Whether to show the keyboard when the window gains focus; see showKeyboardOnFocus. */
    private var keyboardWanted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Not when re-created: that's the same launch, already handled.
        if (savedInstanceState == null && isAddNote(intent)) {
            Log.d(TAG, "onCreate: add note")
            launchAddNoteAt = System.currentTimeMillis()
            showKeyboardOnFocus()
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
            // In front already, the dialog's field can show it by itself.
            if (!hasWindowFocus()) showKeyboardOnFocus()
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
        if (hasFocus && keyboardWanted) {
            keyboardWanted = false
            // The New note dialog focuses its text field as it opens, but
            // when the "+" launches or brings back the app, that's before
            // the window has focus, and Android ignores keyboard requests
            // from a window without it. So ask again now. Posted, because
            // the window's views get input focus only after this returns.
            // If the dialog isn't up yet, this does nothing, and the field
            // shows the keyboard itself when it's focused.
            window.decorView.post {
                val view = currentFocus ?: return@post
                Log.d(TAG, "showing the keyboard")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    view.windowInsetsController?.show(WindowInsets.Type.ime())
                } else {
                    getSystemService(InputMethodManager::class.java).showSoftInput(view, 0)
                }
            }
            // Back to the manifest's mode once Android has acted on it.
            window.decorView.postDelayed({
                window.setSoftInputMode(SOFT_INPUT_STATE_UNSPECIFIED or SOFT_INPUT_ADJUST_RESIZE)
            }, 1000)
        }
    }

    /**
     * Shows the keyboard when the window next gains focus. In the
     * manifest's "unspecified" mode, Android hides the keyboard as a window
     * gains focus, and on Android 16 that wins over the request made then
     * (see onWindowFocusChanged); "always visible" has it show it instead.
     */
    private fun showKeyboardOnFocus() {
        keyboardWanted = true
        window.setSoftInputMode(SOFT_INPUT_STATE_ALWAYS_VISIBLE or SOFT_INPUT_ADJUST_RESIZE)
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
