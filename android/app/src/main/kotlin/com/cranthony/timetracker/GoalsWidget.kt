package com.cranthony.timetracker

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.text.format.DateFormat
import android.text.format.DateUtils
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
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
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import org.json.JSONException
import org.json.JSONObject
import java.util.Calendar

/**
 * The home screen goals: every active goal, the soonest due first, each
 * with when it's due -- "Today", "Tomorrow", a weekday within the week,
 * or the date, and its time if it has one -- the overdue ones' in red.
 * The app keeps them for it as a snapshot (lib/platform/goals_widget.dart),
 * and has it drawn again as they change, as each falls due, and at each
 * midnight, so the days' names keep up.
 *
 * Tapping a goal opens the app on its page, and "Goals" on the Plan
 * page's Goals (see MainActivity); the goal button opens the New goal
 * sheet, as AddGoalWidget does.
 *
 * Each widget's header -- "Goals", and the button -- is at its top, or,
 * set so in its settings (GoalsWidgetConfigureActivity), its bottom.
 */
class GoalsWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val widgetId = GlanceAppWidgetManager(context).getAppWidgetId(id)
        provideContent {
            // A new state each time it's asked to draw again, so now -- and
            // its settings -- are read afresh each time.
            val state = currentState<HomeWidgetGlanceState>()
            val goals = WidgetGoal.parse(state.preferences.getString(SNAPSHOT_KEY, null))
            val atBottom = title.atBottom(context, widgetId)
            GlanceTheme { Content(context, goals, System.currentTimeMillis(), atBottom) }
        }
    }

    companion object {
        /** Where the app keeps the snapshot; see HomeWidgetGoalsHost. */
        const val SNAPSHOT_KEY = "goals_snapshot"

        const val ACTION_SHOW_GOALS = "com.cranthony.timetracker.SHOW_GOALS"
        const val CHANNEL = "time_tracker/goals_widget"

        /** Each widget's "title at the bottom" setting. */
        val title = TitleSetting("goals_widget_settings")

        /**
         * Opens the app on the goal [goal]'s page, or, with none, on the
         * Plan page's Goals. The data URI keeps each tap's intent apart,
         * so none takes another's place.
         */
        fun showGoalsIntent(context: Context, goal: String? = null): Intent {
            val uri = Uri.Builder().scheme("timetracker-widget").authority("goals")
            if (goal != null) uri.appendQueryParameter("goal", goal)
            return Intent(context, MainActivity::class.java)
                .setAction(ACTION_SHOW_GOALS)
                .setData(uri.build())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        /** [intent]'s tap, as the Dart side takes it: "goal". */
        fun tapOf(intent: Intent): Map<String, Any?> =
            mapOf("goal" to intent.data?.getQueryParameter("goal"))
    }
}

/** Draws [GoalsWidget] when the app or its scheduled updates ask. */
class GoalsWidgetReceiver : HomeWidgetGlanceWidgetReceiver<GoalsWidget>() {
    override val glanceAppWidget = GoalsWidget()

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        GoalsWidget.title.forget(context, appWidgetIds)
    }
}

/**
 * One goal of the snapshot: when it's [due] (milliseconds since the
 * epoch; a date's at the midnight after it), if it is, and whether
 * that's a time of day ([hasTime]), not just a date.
 */
private class WidgetGoal(
    val id: String,
    val title: String,
    val due: Long?,
    val hasTime: Boolean,
) {
    companion object {
        /**
         * The snapshot's goals, in its order; null if there isn't one, or
         * it won't read.
         */
        fun parse(json: String?): List<WidgetGoal>? {
            if (json == null) return null
            return try {
                val goals = JSONObject(json).getJSONArray("goals")
                List(goals.length()) { i ->
                    val g = goals.getJSONObject(i)
                    WidgetGoal(
                        id = g.optString("id", ""),
                        title = g.optString("title", ""),
                        due = if (g.isNull("due")) null else g.getLong("due"),
                        hasTime = g.optBoolean("has_time", false),
                    )
                }
            } catch (e: JSONException) {
                null
            }
        }
    }
}

@Composable
private fun Content(
    context: Context,
    goals: List<WidgetGoal>?,
    now: Long,
    titleAtBottom: Boolean,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(GlanceTheme.colors.widgetBackground)
            // No padding of its own: the header runs to the edge, for
            // its button to sit in the corner (its target leaves 2dp
            // round its circle); the goals and the header's title keep
            // 12dp from the sides, and the rows have their own room
            // above and below.
            .cornerRadius(16.dp),
    ) {
        if (!titleAtBottom) Header(context)
        if (goals.isNullOrEmpty()) {
            Text(
                text = if (goals == null) {
                    "Open Time Tracker to show your goals here"
                } else {
                    "No active goals"
                },
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .defaultWeight()
                    .padding(horizontal = 12.dp, vertical = 12.dp)
                    .clickable(open(context)),
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 14.sp),
            )
        } else LazyColumn(
            modifier = GlanceModifier.fillMaxWidth().defaultWeight().padding(horizontal = 12.dp),
        ) {
            for (goal in goals) {
                item(itemId = goal.id.hashCode().toLong()) { GoalRow(context, goal, now) }
            }
        }
        if (titleAtBottom) Header(context)
    }
}

/**
 * "Goals", which opens the Plan page's Goals, then the button for a new
 * goal: above the goals, or below them. Thinner than the calendar's: a
 * compact button, 28dp high, and a smaller title, to leave the goals
 * the room -- six rows in two cells (see [GoalRow]).
 */
@Composable
private fun Header(context: Context) {
    Row(
        // No gap from the goals, and none from the widget's edge: the
        // button's tap target leaves 2dp above and below its circle, and
        // 6dp beside it, so the circle sits in the corner.
        modifier = GlanceModifier.fillMaxWidth().padding(start = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "Goals",
            modifier = GlanceModifier.defaultWeight().clickable(open(context)),
            style = TextStyle(
                color = GlanceTheme.colors.onSurface,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
        HeaderButton(
            R.drawable.ic_add_goal,
            context.getString(R.string.add_goal_widget_label),
            AddGoalWidget.addGoal(context),
            compact = true,
        )
    }
}

/**
 * A goal: its title, and when it's due ([dueLabel]) at the end -- in
 * red, and bold, once it's overdue. Opens its page. [ROW_DP] high, with
 * small text, so six fit in a widget two cells high (150dp on a phone)
 * under the header.
 */
@Composable
private fun GoalRow(context: Context, goal: WidgetGoal, now: Long) {
    val overdue = goal.due != null && goal.due <= now
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(ROW_DP.dp)
            .clickable(open(context, goal = goal.id)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = goal.title.ifBlank { "(no title)" },
            modifier = GlanceModifier.defaultWeight(),
            style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 12.sp),
            maxLines = 1,
        )
        val due = dueLabel(context, goal, now)
        if (due != null) {
            Spacer(modifier = GlanceModifier.width(8.dp))
            Text(
                text = due,
                style = TextStyle(
                    color = if (overdue) GlanceTheme.colors.error else GlanceTheme.colors.onSurfaceVariant,
                    fontSize = 11.sp,
                    fontWeight = if (overdue) FontWeight.Medium else FontWeight.Normal,
                ),
                maxLines = 1,
            )
        }
    }
}

/**
 * A goal's row's height: six of them, under the 28dp header, in the
 * 150dp of two cells, with a few dp over for a launcher that gives less.
 */
private const val ROW_DP = 19

/**
 * When [goal] is due, as of [now]: its day as "Today", "Tomorrow" or
 * "Yesterday", a weekday ("Thu") within the week ahead, or else the date
 * ("Nov 3", with the year when it's another year's); then its time
 * ("5:00 PM", in the phone's clock) if it has one. Null with no
 * deadline.
 */
private fun dueLabel(context: Context, goal: WidgetGoal, now: Long): String? {
    val due = goal.due ?: return null
    // The day it's due: a date's is the one before its midnight.
    val day = if (goal.hasTime) due else due - 1
    val days = epochDay(day) - epochDay(now)
    val dayLabel = when {
        days == 0L -> "Today"
        days == 1L -> "Tomorrow"
        days == -1L -> "Yesterday"
        days in 2L..6L -> DateUtils.formatDateTime(
            context,
            day,
            DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_ABBREV_WEEKDAY,
        )
        else -> DateUtils.formatDateTime(
            context,
            day,
            DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH,
        )
    }
    return if (goal.hasTime) "$dayLabel ${DateFormat.getTimeFormat(context).format(due)}" else dayLabel
}

/**
 * The day [millis] is in, as a count of days, in the phone's time zone:
 * the midnight the day starts at, moved on to its noon, in days since
 * the epoch, so a day's number is the same whatever the hour, and the
 * clocks going forward or back don't change it.
 */
private fun epochDay(millis: Long): Long {
    val midnight = Calendar.getInstance().apply {
        timeInMillis = millis
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis
    return Math.floorDiv(midnight + DateUtils.DAY_IN_MILLIS / 2, DateUtils.DAY_IN_MILLIS)
}

private fun open(context: Context, goal: String? = null): Action =
    actionStartActivity(GoalsWidget.showGoalsIntent(context, goal))
