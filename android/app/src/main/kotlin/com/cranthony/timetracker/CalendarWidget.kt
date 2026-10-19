package com.cranthony.timetracker

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
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
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
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
 * Each day's header also gives its weather, while it's on: its chance
 * of rain, its high and low, and its sky -- today's, what's left of it --
 * as the app keeps them apart (calendar_weather), redrawing it with each
 * forecast. Too narrow for all of it, the high and low go first.
 *
 * Under each day's header are the active goals due that day: the two
 * due soonest, a line each, so together they're an event's height --
 * and how many more there are.
 *
 * Tapping an event, a day, or the header opens the app on Events there
 * (see MainActivity); the "+" opens the New note dialog, as AddNoteWidget
 * does.
 *
 * Each widget's header -- "Calendar", and the "+" -- is at its top, or,
 * set so in its settings (CalendarWidgetConfigureActivity), its bottom.
 */
class CalendarWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val widgetId = GlanceAppWidgetManager(context).getAppWidgetId(id)
        provideContent {
            // A new state each time it's asked to draw again, so now -- and
            // its settings -- are read afresh each time.
            val state = currentState<HomeWidgetGlanceState>()
            val days = CalendarDay.parse(state.preferences.getString(SNAPSHOT_KEY, null))
            val weather = DayWeather.parse(state.preferences.getString(WEATHER_KEY, null))
            val atBottom = titleAtBottom(context, widgetId)
            GlanceTheme { Content(context, days, weather, System.currentTimeMillis(), atBottom) }
        }
    }

    companion object {
        /** Where the app keeps the snapshot; see HomeWidgetHost. */
        const val SNAPSHOT_KEY = "calendar_snapshot"

        /** Where the app keeps each day's weather; see HomeWidgetHost. */
        const val WEATHER_KEY = "calendar_weather"

        const val ACTION_SHOW_EVENTS = "com.cranthony.timetracker.SHOW_EVENTS"
        const val CHANNEL = "time_tracker/calendar_widget"

        /** Where each widget's settings are kept, by its id. */
        private const val SETTINGS = "calendar_widget_settings"

        private fun titleAtBottomKey(widgetId: Int) = "title_at_bottom_$widgetId"

        /** Whether widget [widgetId]'s header is at its bottom. */
        fun titleAtBottom(context: Context, widgetId: Int): Boolean =
            context.getSharedPreferences(SETTINGS, Context.MODE_PRIVATE)
                .getBoolean(titleAtBottomKey(widgetId), false)

        fun setTitleAtBottom(context: Context, widgetId: Int, atBottom: Boolean) {
            context.getSharedPreferences(SETTINGS, Context.MODE_PRIVATE).edit()
                .putBoolean(titleAtBottomKey(widgetId), atBottom)
                .apply()
        }

        /** Forgets the settings of the widgets [widgetIds], removed. */
        fun forget(context: Context, widgetIds: IntArray) {
            val edit = context.getSharedPreferences(SETTINGS, Context.MODE_PRIVATE).edit()
            for (widgetId in widgetIds) edit.remove(titleAtBottomKey(widgetId))
            edit.apply()
        }

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

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        CalendarWidget.forget(context, appWidgetIds)
    }
}

/**
 * One day of the snapshot: from [start] to [end], its events, and the
 * first of the goals due in it and how many more there are.
 */
private class CalendarDay(
    val start: Long,
    val end: Long,
    val events: List<CalendarEvent>,
    val goals: List<CalendarGoal> = emptyList(),
    val moreGoals: Int = 0,
) {
    companion object {
        /** The snapshot's days; none if there isn't one, or it won't read. */
        fun parse(json: String?): List<CalendarDay> {
            if (json == null) return emptyList()
            return try {
                val days = JSONObject(json).getJSONArray("days")
                List(days.length()) { i ->
                    val day = days.getJSONObject(i)
                    val events = day.getJSONArray("events")
                    val goals = day.optJSONArray("goals")
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
                        goals = List(goals?.length() ?: 0) { j ->
                            val g = goals!!.getJSONObject(j)
                            CalendarGoal(
                                id = g.optString("id", ""),
                                title = g.optString("title", ""),
                            )
                        },
                        moreGoals = day.optInt("more_goals", 0),
                    )
                }
            } catch (e: org.json.JSONException) {
                emptyList()
            }
        }
    }
}

/**
 * A day's weather, for its header: its sky as an emoji, its chance of
 * rain ("40%", if any), and its high and low ("72° / 55°", and compact,
 * "72/55°"), if they're known.
 */
private class DayWeather(
    val icon: String,
    val rain: String?,
    val temps: String?,
    val tempsCompact: String?,
) {
    companion object {
        /** Each day's, by its start; none if there isn't any, or it won't read. */
        fun parse(json: String?): Map<Long, DayWeather> {
            if (json == null) return emptyMap()
            return try {
                val days = JSONObject(json).getJSONArray("days")
                (0 until days.length()).associate { i ->
                    val day = days.getJSONObject(i)
                    fun text(key: String) = if (day.isNull(key)) null else day.optString(key, "").ifEmpty { null }
                    day.getLong("start") to DayWeather(
                        icon = day.optString("icon", ""),
                        rain = text("rain"),
                        temps = text("temps"),
                        tempsCompact = text("temps_compact"),
                    )
                }
            } catch (e: org.json.JSONException) {
                emptyMap()
            }
        }
    }
}

private class CalendarGoal(val id: String, val title: String)

private class CalendarEvent(
    val id: String?,
    val summary: String?,
    val start: Long,
    val end: Long,
    val color: Int,
)

@Composable
private fun Content(
    context: Context,
    days: List<CalendarDay>,
    weather: Map<Long, DayWeather>,
    now: Long,
    titleAtBottom: Boolean,
) {
    // What's over is left out: the days that have ended, and their events.
    val shown = days.filter { it.end > now }.map { day ->
        CalendarDay(day.start, day.end, day.events.filter { it.end > now }, day.goals, day.moreGoals)
    }
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(16.dp)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        if (!titleAtBottom) Header(context, atBottom = false)
        if (shown.isEmpty()) {
            Text(
                text = if (days.isEmpty()) {
                    "Open Time Tracker to show your calendar here"
                } else {
                    "Open Time Tracker to show the days ahead"
                },
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .defaultWeight()
                    .padding(vertical = 12.dp)
                    .clickable(open(context)),
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 14.sp),
            )
        } else LazyColumn(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
            for (day in shown) {
                item(itemId = day.start) { DayHeader(context, day, weather[day.start], now) }
                day.goals.forEachIndexed { i, goal ->
                    item(itemId = ("goal:" + goal.id).hashCode().toLong() * 31 + day.start) {
                        val more = if (i == day.goals.lastIndex) day.moreGoals else 0
                        GoalRow(context, day, goal, more, now)
                    }
                }
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
        if (titleAtBottom) Header(context, atBottom = true)
    }
}

/**
 * "Calendar", which opens Events at now, and the "+" for a new note:
 * above the days, or, [atBottom], below them.
 */
@Composable
private fun Header(context: Context, atBottom: Boolean) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(top = if (atBottom) 4.dp else 0.dp, bottom = if (atBottom) 0.dp else 4.dp),
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

/**
 * "Today", "Tomorrow", or the date; then its [weather], if there is any:
 * its chance of rain, its high and low, and its sky. Where they don't all
 * fit, the day's named shorter ("Thu"), then the high and low compact,
 * then left out. Opens Events on that day.
 */
@Composable
private fun DayHeader(context: Context, day: CalendarDay, weather: DayWeather?, now: Long) {
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
    val shortLabel = if (today) {
        label
    } else {
        DateUtils.formatDateTime(
            context,
            day.start,
            DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_ABBREV_WEEKDAY,
        )
    }
    val (shown, temps) = if (weather == null) {
        label to null
    } else {
        // The header's width: the widget's, less its padding.
        val room = LocalSize.current.width.value - 24f
        val scale = context.resources.configuration.fontScale
        // The day's name at its size, then the weather's parts at theirs.
        fun width(name: String, vararg parts: String?): Float {
            val present = parts.filterNotNull()
            val text = textWidth(name, LABEL_SP) +
                present.sumOf { textWidth(it, WEATHER_SP).toDouble() }.toFloat()
            return text * scale + HEADER_GAP * present.size
        }
        val icon = weather.icon
        val rain = weather.rain?.let { "💧$it" }
        listOf(
            label to weather.temps,
            shortLabel to weather.temps,
            shortLabel to weather.tempsCompact,
            shortLabel to null,
        ).firstOrNull { (name, t) -> width(name, icon, rain, t) <= room }
            ?: (shortLabel to null)
    }
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(top = 8.dp, bottom = 2.dp)
            .clickable(open(context, at = if (today) null else day.start)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = shown,
            modifier = GlanceModifier.defaultWeight(),
            style = TextStyle(
                color = GlanceTheme.colors.primary,
                fontSize = LABEL_SP.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
        if (weather != null) {
            weather.rain?.let {
                Spacer(modifier = GlanceModifier.width(HEADER_GAP.dp))
                Text(
                    text = "💧$it",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF1E88E5)),
                        fontSize = WEATHER_SP.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    maxLines = 1,
                )
            }
            temps?.let {
                Spacer(modifier = GlanceModifier.width(HEADER_GAP.dp))
                Text(
                    text = it,
                    style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = WEATHER_SP.sp),
                    maxLines = 1,
                )
            }
            Spacer(modifier = GlanceModifier.width(HEADER_GAP.dp))
            Text(text = weather.icon, style = TextStyle(fontSize = WEATHER_SP.sp), maxLines = 1)
        }
    }
}

/** The space before each of a header's weather's parts, in dp. */
private const val HEADER_GAP = 4f

/** The day's name's text size, and the weather's, in sp. */
private const val LABEL_SP = 13f
private const val WEATHER_SP = 12f

/**
 * About how wide [text] is at [sp], in dp at the phone's usual text
 * size: a letter or digit about half as wide as it's tall, an emoji a
 * little wider than tall. Measured against the emulator's widget: at 3
 * cells wide, every day's chance of rain and high and low fit.
 */
private fun textWidth(text: String, sp: Float): Float {
    var width = 0f
    var i = 0
    while (i < text.length) {
        val point = text.codePointAt(i)
        width += when {
            // The selector that asks for an emoji's color: no width.
            point == 0xFE0F -> 0f
            point >= 0x2190 -> 1.2f * sp
            else -> 0.55f * sp
        }
        i += Character.charCount(point)
    }
    return width
}

/**
 * A goal due that [day]: the goal icon and its title, on one line, half
 * an event's height; and, if [more] isn't zero, "+[more]" at its end for
 * the goals not shown. Opens Events on that day.
 */
@Composable
private fun GoalRow(context: Context, day: CalendarDay, goal: CalendarGoal, more: Int, now: Long) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(GOAL_ROW_DP.dp)
            .clickable(open(context, at = if (day.start <= now) null else day.start)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            provider = ImageProvider(goalIcon),
            contentDescription = "Goal",
            modifier = GlanceModifier.size(14.dp),
            colorFilter = ColorFilter.tint(GlanceTheme.colors.onSurface),
        )
        Spacer(modifier = GlanceModifier.width(6.dp))
        Text(
            text = goal.title.ifBlank { "(no title)" },
            modifier = GlanceModifier.defaultWeight(),
            style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 12.sp),
            maxLines = 1,
        )
        if (more > 0) {
            Spacer(modifier = GlanceModifier.width(4.dp))
            Text(
                text = "+$more",
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 12.sp),
                maxLines = 1,
            )
        }
    }
}

/** A goal's row's height: half an event's, its 32dp bar and padding. */
private const val GOAL_ROW_DP = 19

/**
 * The app's goal icon (GoalPainter, lib/widgets/goal_icon.dart), in white
 * to be tinted: a bullseye with an arrow stuck in the middle, come in
 * from the upper right, a gap cut round the arrow where it crosses the
 * rings. Drawn once, on a 24-unit square as the app's is.
 */
private val goalIcon: Bitmap by lazy { drawGoalIcon() }

private fun drawGoalIcon(): Bitmap {
    val px = 64
    val bitmap = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(px / 24f, px / 24f)
    val center = PointF(10f, 14f)
    val tail = PointF(21.6f, 2.4f)
    val length = Math.hypot((tail.x - center.x).toDouble(), (tail.y - center.y).toDouble()).toFloat()
    val along = PointF((tail.x - center.x) / length, (tail.y - center.y) / length)
    val across = PointF(-along.y, along.x)
    // [a] along the arrow from [from], and [b] across it.
    fun at(from: PointF, a: Float, b: Float = 0f) =
        PointF(from.x + along.x * a + across.x * b, from.y + along.y * a + across.y * b)
    val shaft = 1.5f
    val halo = 0.9f
    val vaneLength = 4.8f
    val vaneReach = 1.9f
    val back = at(tail, -0.9f)
    val front = at(back, -vaneLength)
    val vanes = listOf(1f, -1f).map { side ->
        val outerFront = at(back, -(vaneLength - 1.8f), side * vaneReach)
        val outerBack = at(back, 0.5f, side * vaneReach)
        Path().apply {
            moveTo(front.x, front.y)
            lineTo(outerFront.x, outerFront.y)
            lineTo(outerBack.x, outerBack.y)
            lineTo(back.x, back.y)
            close()
        }
    }
    fun paint(clear: Boolean = false, stroke: Float? = null) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.WHITE
        if (clear) xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
        if (stroke != null) {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
    }
    canvas.drawCircle(center.x, center.y, 9f, paint(stroke = 2.2f))
    canvas.drawCircle(center.x, center.y, 5.1f, paint(stroke = 2.2f))
    canvas.drawCircle(center.x, center.y, 2.2f, paint())
    // A gap round the arrow where it crosses the rings, then the arrow.
    val haloFrom = at(center, 2.6f)
    canvas.drawLine(haloFrom.x, haloFrom.y, tail.x, tail.y, paint(clear = true, stroke = shaft + halo * 2))
    for (vane in vanes) {
        canvas.drawPath(vane, paint(clear = true, stroke = halo * 2))
        canvas.drawPath(vane, paint(clear = true))
    }
    canvas.drawLine(center.x, center.y, tail.x, tail.y, paint(stroke = shaft))
    for (vane in vanes) canvas.drawPath(vane, paint())
    return bitmap
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

