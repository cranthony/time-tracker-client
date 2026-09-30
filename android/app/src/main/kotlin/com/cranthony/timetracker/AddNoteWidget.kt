package com.cranthony.timetracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * A one-cell home screen button that opens the app straight into its New
 * note dialog. MainActivity hands the tap to the Dart side (see
 * lib/platform/add_note_shortcut.dart), which opens the dialog.
 */
class AddNoteWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(ACTION_ADD_NOTE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val onClick = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val views = RemoteViews(context.packageName, R.layout.add_note_widget)
        views.setOnClickPendingIntent(R.id.add_note_button, onClick)
        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }

    companion object {
        const val ACTION_ADD_NOTE = "com.cranthony.timetracker.ADD_NOTE"
        const val CHANNEL = "time_tracker/add_note_shortcut"
    }
}
