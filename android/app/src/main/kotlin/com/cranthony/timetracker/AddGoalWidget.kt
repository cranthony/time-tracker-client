package com.cranthony.timetracker

import android.content.Context
import android.content.Intent
import androidx.glance.GlanceId
import androidx.glance.action.Action
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent

/**
 * A one-cell home screen button that opens the app straight into its New
 * goal sheet, as AddNoteWidget does its New note one. MainActivity hands
 * the tap to the Dart side (see lib/platform/add_note_shortcut.dart),
 * which opens the sheet.
 */
class AddGoalWidget : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AddGoalButton()

    companion object {
        const val ACTION_ADD_GOAL = "com.cranthony.timetracker.ADD_GOAL"

        /** Opens the app into its New goal sheet; the calendar's goal button too. */
        fun addGoal(context: Context): Action =
            actionStartActivity(
                Intent(context, MainActivity::class.java)
                    .setAction(ACTION_ADD_GOAL)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
    }
}

private class AddGoalButton : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val label = context.getString(R.string.add_goal_widget_label)
        provideContent {
            RoundButtonCell(R.drawable.ic_add_goal, label, AddGoalWidget.addGoal(context))
        }
    }
}
