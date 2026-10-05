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

    /**
     * An add-note request waiting to show the keyboard, until the window
     * has focus and the dialog's field is ready, in either order; see
     * awaitKeyboard.
     */
    private var keyboardWanted = false

    /** Whether the New note dialog's field has focus; see "fieldReady". */
    private var fieldReady = false

    /** Gives up on a keyboard that never got both; see awaitKeyboard. */
    private val giveUpOnKeyboard = Runnable {
        if (keyboardWanted) {
            Log.d(TAG, "gave up waiting to show the keyboard")
            keyboardWanted = false
            restoreSoftInputMode()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Not when re-created: that's the same launch, already handled.
        if (savedInstanceState == null && isAddNote(intent)) {
            Log.d(TAG, "onCreate: add note")
            launchAddNoteAt = System.currentTimeMillis()
            awaitKeyboard()
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
                } else if (call.method == "fieldReady") {
                    Log.d(TAG, "fieldReady")
                    fieldReady = true
                    showKeyboardIfReady()
                    result.success(null)
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
            if (!hasWindowFocus()) awaitKeyboard()
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
        if (hasFocus) showKeyboardIfReady()
    }

    /**
     * Shows the keyboard for an add-note request once both the window has
     * focus and the dialog's field does. The field asks for the keyboard
     * itself as it's focused, but when the "+" launches or brings back the
     * app, that's often before the window has focus, and Android ignores
     * keyboard requests from a window without it. Whichever comes second
     * asks again here. Asking before the field is focused would be for
     * the FlutterView with no text input behind it, so it waits for both.
     *
     * In the manifest's "unspecified" mode, Android hides the keyboard as
     * a window gains focus, and on Android 16 that wins over a request
     * made then; "always visible" stops that until the keyboard is shown.
     */
    private fun awaitKeyboard() {
        keyboardWanted = true
        fieldReady = false
        window.setSoftInputMode(SOFT_INPUT_STATE_ALWAYS_VISIBLE or SOFT_INPUT_ADJUST_RESIZE)
        // A slow cold start takes a few seconds; a dialog that never
        // opens (one was open already) never says it's ready.
        window.decorView.removeCallbacks(giveUpOnKeyboard)
        window.decorView.postDelayed(giveUpOnKeyboard, 10_000)
    }

    private fun showKeyboardIfReady() {
        if (!keyboardWanted || !fieldReady || !hasWindowFocus()) return
        keyboardWanted = false
        window.decorView.removeCallbacks(giveUpOnKeyboard)
        // Posted, because just after the window gains focus its views get
        // input focus only once onWindowFocusChanged returns.
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
        window.decorView.postDelayed({ restoreSoftInputMode() }, 1000)
    }

    private fun restoreSoftInputMode() {
        // Unless another request came since.
        if (keyboardWanted) return
        window.setSoftInputMode(SOFT_INPUT_STATE_UNSPECIFIED or SOFT_INPUT_ADJUST_RESIZE)
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
