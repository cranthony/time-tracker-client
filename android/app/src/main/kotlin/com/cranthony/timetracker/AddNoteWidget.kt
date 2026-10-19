package com.cranthony.timetracker

import android.content.Context
import android.content.Intent
import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics

/**
 * A one-cell home screen button that opens the app straight into its New
 * note dialog. MainActivity hands the tap to the Dart side (see
 * lib/platform/add_note_shortcut.dart), which opens the dialog.
 *
 * The receiver keeps its name from before it was drawn with Glance, so
 * the buttons already on home screens stay.
 */
class AddNoteWidget : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AddNoteButton()

    companion object {
        const val ACTION_ADD_NOTE = "com.cranthony.timetracker.ADD_NOTE"
        const val CHANNEL = "time_tracker/add_note_shortcut"

        /** Opens the app into its New note dialog; the calendar's "+" too. */
        fun addNote(context: Context): Action =
            actionStartActivity(
                Intent(context, MainActivity::class.java)
                    .setAction(ACTION_ADD_NOTE)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
    }
}

private class AddNoteButton : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val label = context.getString(R.string.add_note_widget_label)
        provideContent {
            RoundButtonCell(R.drawable.ic_add_note, label, AddNoteWidget.addNote(context))
        }
    }
}

/**
 * A one-cell button: [icon] in a round teal button in its middle, the
 * whole cell the tap target, doing [action]. The Add note and Add goal
 * widgets' both.
 */
@Composable
fun RoundButtonCell(@DrawableRes icon: Int, label: String, action: Action) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .clickable(action)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        // Teal, like the app's colour scheme; round on every Android
        // version, as cornerRadius is only from 12 on.
        Box(
            modifier = GlanceModifier
                .size(56.dp)
                .background(ImageProvider(R.drawable.add_note_widget_background))
                .padding(14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                provider = ImageProvider(icon),
                contentDescription = null,
                modifier = GlanceModifier.fillMaxSize(),
            )
        }
    }
}
