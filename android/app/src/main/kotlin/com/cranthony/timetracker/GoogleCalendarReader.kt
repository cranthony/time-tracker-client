package com.cranthony.timetracker

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The phone's Google calendars, read from Android's calendar provider --
 * what the Google Calendar app syncs -- for the Events page to show
 * their events beside the user's own. Nothing here goes to the server.
 *
 * Over [CHANNEL]:
 * - "permission": "granted", "denied", or "blocked" (denied for good:
 *   only the app's settings can allow it now).
 * - "requestPermission": asks, and says as "permission" does.
 * - "calendars": each Google calendar's id, account, name, color and
 *   whether it's the account's own.
 * - "events" (from, to: ms since the epoch; calendarIds): each event's
 *   occurrence overlapping them, but those the user declined.
 * - "openEvent" (id, begin, end): opens it in the calendar app.
 * - "openSettings": opens the app's settings, to allow it there.
 */
class GoogleCalendarReader(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The answer to "requestPermission", once Android has asked. */
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permission" -> result.success(permission(asked = false))
            "requestPermission" -> request(result)
            "calendars" -> inBackground(result) { calendars() }
            "events" -> {
                val from = (call.argument<Number>("from") ?: 0).toLong()
                val to = (call.argument<Number>("to") ?: 0).toLong()
                val ids = call.argument<List<String>>("calendarIds") ?: emptyList()
                inBackground(result) { events(from, to, ids) }
            }
            "openEvent" -> {
                val id = call.argument<String>("id")?.toLongOrNull()
                if (id == null) {
                    result.success(false)
                    return
                }
                val intent = Intent(
                    Intent.ACTION_VIEW,
                    ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id),
                ).apply {
                    call.argument<Number>("begin")?.let {
                        putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, it.toLong())
                    }
                    call.argument<Number>("end")?.let {
                        putExtra(CalendarContract.EXTRA_EVENT_END_TIME, it.toLong())
                    }
                }
                result.success(start(intent))
            }
            "openSettings" -> result.success(
                start(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null),
                    ),
                ),
            )
            else -> result.notImplemented()
        }
    }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        Log.w(TAG, "nothing to open $intent", e)
        false
    }

    private fun granted(): Boolean =
        activity.checkSelfPermission(Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Whether it may read them; [asked], just after asking, a denial
     * Android won't ask about again is "blocked".
     */
    private fun permission(asked: Boolean): String = when {
        granted() -> "granted"
        asked && !activity.shouldShowRequestPermissionRationale(
            Manifest.permission.READ_CALENDAR,
        ) -> "blocked"
        else -> "denied"
    }

    private fun request(result: MethodChannel.Result) {
        if (granted()) {
            result.success("granted")
            return
        }
        pending?.success(permission(asked = false))
        pending = result
        activity.requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), REQUEST_CODE)
    }

    /** From MainActivity's onRequestPermissionsResult: whether it was ours. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pending?.success(permission(asked = true))
        pending = null
        return true
    }

    private fun inBackground(result: MethodChannel.Result, read: () -> Any?) {
        if (!granted()) {
            result.error("permission", "Not allowed to read calendars", null)
            return
        }
        io.execute {
            try {
                val value = read()
                main.post { result.success(value) }
            } catch (e: Exception) {
                Log.w(TAG, "reading calendars failed", e)
                main.post { result.error("read", e.message, null) }
            }
        }
    }

    private fun calendars(): List<Map<String, Any?>> {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.CALENDAR_COLOR,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.OWNER_ACCOUNT,
        )
        val list = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            "${CalendarContract.Calendars.ACCOUNT_TYPE} = ? AND " +
                "${CalendarContract.Calendars.SYNC_EVENTS} = 1",
            arrayOf(GOOGLE),
            "${CalendarContract.Calendars.ACCOUNT_NAME}, " +
                "${CalendarContract.Calendars.IS_PRIMARY} DESC, " +
                CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val account = cursor.getString(1)
                list.add(
                    mapOf(
                        "id" to cursor.getLong(0).toString(),
                        "account" to account,
                        "name" to (cursor.getString(2) ?: account),
                        "color" to cursor.getInt(3),
                        // Its own calendar: marked so, or owned by it.
                        "isPrimary" to (cursor.getInt(4) == 1 ||
                            (account != null && account == cursor.getString(5))),
                    ),
                )
            }
        }
        return list
    }

    private fun events(from: Long, to: Long, calendarIds: List<String>): List<Map<String, Any?>> {
        val ids = calendarIds.mapNotNull { it.toLongOrNull() }
        if (ids.isEmpty() || to <= from) return emptyList()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, from)
            ContentUris.appendId(it, to)
        }.build()
        val projection = arrayOf(
            CalendarContract.Instances._ID,
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.DISPLAY_COLOR,
            CalendarContract.Instances.SELF_ATTENDEE_STATUS,
        )
        val list = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(
            uri,
            projection,
            "${CalendarContract.Instances.CALENDAR_ID} IN " +
                ids.joinToString(",", "(", ")") +
                // Not those the user declined; those with no one invited
                // have no status.
                " AND (${CalendarContract.Instances.SELF_ATTENDEE_STATUS} IS NULL OR " +
                "${CalendarContract.Instances.SELF_ATTENDEE_STATUS} != " +
                "${CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED})",
            null,
            "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                list.add(
                    mapOf(
                        "id" to "${cursor.getLong(1)}@${cursor.getLong(4)}",
                        "eventId" to cursor.getLong(1).toString(),
                        "calendarId" to cursor.getLong(2).toString(),
                        "title" to cursor.getString(3),
                        // All day, these are midnights in UTC.
                        "begin" to cursor.getLong(4),
                        "end" to cursor.getLong(5),
                        "allDay" to (cursor.getInt(6) == 1),
                        "location" to cursor.getString(7),
                        "description" to cursor.getString(8),
                        "color" to cursor.getInt(9),
                    ),
                )
            }
        }
        return list
    }

    companion object {
        const val CHANNEL = "time_tracker/google_calendar"
        private const val REQUEST_CODE = 4217
        private const val GOOGLE = "com.google"
        private const val TAG = "TimeTracker"
    }
}
