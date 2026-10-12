package com.cranthony.timetracker

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.text.format.DateFormat
import android.text.format.DateUtils
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import org.json.JSONObject

/**
 * The home screen calendar: the events from now to a few days ahead,
 * under a header for each day. The app keeps them for it as a snapshot
 * (lib/platform/calendar_widget.dart), and has it drawn again as they
 * change, and as each event starts or ends; what's over is left out
 * as it's drawn, so it always starts at now.
 *
 * Tapping an event, a day, or the header opens the app on Events there
 * (see MainActivity); the "+" opens the New note dialog, as AddNoteWidget
 * does.
 */
class CalendarWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            // A new state each time it's asked to draw again, so now is
            // read afresh each time.
            val state = currentState<HomeWidgetGlanceState>()
            val days = CalendarDay.parse(state.preferences.getString(SNAPSHOT_KEY, null))
            GlanceTheme { Content(context, days, System.currentTimeMillis()) }
        }
    }

    companion object {
        /** Where the app keeps the snapshot; see HomeWidgetHost. */
        const val SNAPSHOT_KEY = "calendar_snapshot"

        const val ACTION_SHOW_EVENTS = "com.cranthony.timetracker.SHOW_EVENTS"
        const val CHANNEL = "time_tracker/calendar_widget"

        /**
         * Opens Events at [at] (milliseconds since the epoch), on [event] if
         * it's given; at now with neither. The data URI keeps each tap's
         * intent apart, so none takes another's place.
         */
        fun showEventsIntent(context: Context, at: Long? = null, event: String? = null): Intent {
            val uri = Uri.Builder().scheme("timetracker-widget").authority("events")
            if (at != null) uri.appendQueryParameter("at", at.toString())
            if (event != null) uri.appendQueryParameter("event", event)
            return Intent(context, MainActivity::class.java)
                .setAction(ACTION_SHOW_EVENTS)
                .setData(uri.build())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        /** [intent]'s tap, as the Dart side takes it: "at" and "event". */
        fun tapOf(intent: Intent): Map<String, Any?> {
            val uri = intent.data
            return mapOf(
                "at" to uri?.getQueryParameter("at")?.toLongOrNull(),
                "event" to uri?.getQueryParameter("event"),
            )
        }
    }
}

/** Draws [CalendarWidget] when the app or its scheduled updates ask. */
class CalendarWidgetReceiver : HomeWidgetGlanceWidgetReceiver<CalendarWidget>() {
    override val glanceAppWidget = CalendarWidget()
}

/** One day of the snapshot: from [start] to [end], and its events. */
private class CalendarDay(val start: Long, val end: Long, val events: List<CalendarEvent>) {
    companion object {
        /** The snapshot's days; none if there isn't one, or it won't read. */
        fun parse(json: String?): List<CalendarDay> {
            if (json == null) return emptyList()
            return try {
                val days = JSONObject(json).getJSONArray("days")
                List(days.length()) { i ->
                    val day = days.getJSONObject(i)
                    val events = day.getJSONArray("events")
                    CalendarDay(
                        start = day.getLong("start"),
                        end = day.getLong("end"),
                        events = List(events.length()) { j ->
                            val e = events.getJSONObject(j)
                            CalendarEvent(
                                id = if (e.isNull("id")) null else e.getString("id"),
                                summary = if (e.isNull("summary")) null else e.getString("summary"),
                                start = e.getLong("start"),
                                end = e.getLong("end"),
                                color = e.getLong("color").toInt(),
                            )
                        },
                    )
                }
            } catch (e: org.json.JSONException) {
                emptyList()
            }
        }
    }
}

private class CalendarEvent(
    val id: String?,
    val summary: String?,
    val start: Long,
    val end: Long,
    val color: Int,
)

@Composable
private fun Content(context: Context, days: List<CalendarDay>, now: Long) {
    // What's over is left out: the days that have ended, and their events.
    val shown = days.filter { it.end > now }.map { day ->
        CalendarDay(day.start, day.end, day.events.filter { it.end > now })
    }
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(16.dp)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Header(context)
        if (shown.isEmpty()) {
            Text(
                text = if (days.isEmpty()) {
                    "Open Time Tracker to show your calendar here"
                } else {
                    "Open Time Tracker to show the days ahead"
                },
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp)
                    .clickable(open(context)),
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 14.sp),
            )
            return@Column
        }
        LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
            for (day in shown) {
                item(itemId = day.start) { DayHeader(context, day, now) }
                if (day.events.isEmpty()) {
                    item(itemId = day.start + 1) {
                        Text(
                            text = "Nothing planned",
                            modifier = GlanceModifier.fillMaxWidth().padding(vertical = 4.dp),
                            style = TextStyle(
                                color = GlanceTheme.colors.onSurfaceVariant,
                                fontSize = 13.sp,
                            ),
                        )
                    }
                }
                for (event in day.events) {
                    // An event across midnight is in each day it's in.
                    item(itemId = (event.id ?: "${event.start}").hashCode().toLong() * 31 + day.start) {
                        EventRow(context, day, event, now)
                    }
                }
            }
        }
    }
}

/** "Calendar", which opens Events at now, and the "+" for a new note. */
@Composable
private fun Header(context: Context) {
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "Calendar",
            modifier = GlanceModifier.defaultWeight().clickable(open(context)),
            style = TextStyle(
                color = GlanceTheme.colors.onSurface,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
        Box(
            modifier = GlanceModifier
                .size(32.dp)
                .cornerRadius(16.dp)
                .background(GlanceTheme.colors.primary)
                .clickable(AddNoteWidget.addNote(context)),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                provider = ImageProvider(R.drawable.ic_add_note),
                contentDescription = context.getString(R.string.add_note_widget_label),
                modifier = GlanceModifier.size(20.dp),
                colorFilter = ColorFilter.tint(GlanceTheme.colors.onPrimary),
            )
        }
    }
}

/** "Today", "Tomorrow", or the date; opens Events on that day. */
@Composable
private fun DayHeader(context: Context, day: CalendarDay, now: Long) {
    val today = day.start <= now
    val label = when {
        today -> "Today"
        DateUtils.isToday(day.start - DateUtils.DAY_IN_MILLIS) -> "Tomorrow"
        else -> DateUtils.formatDateTime(
            context,
            day.start,
            DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_SHOW_DATE or
                DateUtils.FORMAT_ABBREV_ALL or DateUtils.FORMAT_NO_YEAR,
        )
    }
    Text(
        text = label,
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(top = 8.dp, bottom = 2.dp)
            .clickable(open(context, at = if (today) null else day.start)),
        style = TextStyle(
            color = GlanceTheme.colors.primary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
        ),
        maxLines = 1,
    )
}

/** Its color, times and summary; opens Events on it. */
@Composable
private fun EventRow(context: Context, day: CalendarDay, event: CalendarEvent, now: Long) {
    val going = event.start <= now
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .clickable(open(context, at = event.start, event = event.id)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = GlanceModifier
                .width(4.dp)
                .height(32.dp)
                .cornerRadius(2.dp)
                .background(ColorProvider(Color(event.color))),
        ) {}
        Spacer(modifier = GlanceModifier.width(8.dp))
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = event.summary?.takeIf { it.isNotBlank() } ?: "(no title)",
                style = TextStyle(
                    color = GlanceTheme.colors.onSurface,
                    fontSize = 14.sp,
                    fontWeight = if (going) FontWeight.Bold else FontWeight.Normal,
                ),
                maxLines = 1,
            )
            Text(
                text = times(context, day, event, going),
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 12.sp),
                maxLines = 1,
            )
        }
    }
}

/**
 * "9:00 – 10:00", in the phone's 12 or 24 hour clock; "Now · until 10:00"
 * while it's on; and where it's not all in [day], from or until midnight.
 */
private fun times(context: Context, day: CalendarDay, event: CalendarEvent, going: Boolean): String {
    val format = DateFormat.getTimeFormat(context)
    val start = format.format(event.start)
    val end = format.format(event.end)
    val fromBefore = event.start < day.start
    val untilAfter = event.end > day.end
    return when {
        going && untilAfter -> "Now · until " + DateUtils.formatDateTime(
            context,
            event.end,
            DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_SHOW_TIME or DateUtils.FORMAT_ABBREV_ALL,
        )
        going -> "Now · until $end"
        fromBefore && untilAfter -> "All day"
        fromBefore -> "Until $end"
        untilAfter -> "From $start"
        else -> "$start – $end"
    }
}

private fun open(context: Context, at: Long? = null, event: String? = null): Action =
    actionStartActivity(CalendarWidget.showEventsIntent(context, at, event))

