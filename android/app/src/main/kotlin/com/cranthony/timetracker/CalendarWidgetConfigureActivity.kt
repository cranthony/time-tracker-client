package com.cranthony.timetracker

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup

/**
 * One home screen calendar's settings: whether its title -- "Calendar",
 * and the "+" -- is at its top or its bottom. Android opens it from the
 * widget's settings (from Android 12, holding it down), and, before
 * that, as it's added. Done keeps the choice, for that widget alone,
 * and draws it again; backed out of, it's left as it was.
 */
class CalendarWidgetConfigureActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Until Done: being added, as before Android 12, it's not added.
        setResult(RESULT_CANCELED)
        val widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        setTitle(R.string.calendar_widget_settings_title)

        val atBottom = CalendarWidget.titleAtBottom(this, widgetId)
        val top = RadioButton(this).apply {
            id = View.generateViewId()
            setText(R.string.calendar_widget_title_top)
        }
        val bottom = RadioButton(this).apply {
            id = View.generateViewId()
            setText(R.string.calendar_widget_title_bottom)
        }
        val choice = RadioGroup(this).apply {
            addView(top)
            addView(bottom)
            check(if (atBottom) bottom.id else top.id)
        }
        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            addView(Button(this@CalendarWidgetConfigureActivity, null, android.R.attr.buttonBarButtonStyle).apply {
                setText(android.R.string.cancel)
                setOnClickListener { finish() }
            })
            addView(Button(this@CalendarWidgetConfigureActivity, null, android.R.attr.buttonBarButtonStyle).apply {
                setText(R.string.calendar_widget_settings_done)
                setOnClickListener {
                    CalendarWidget.setTitleAtBottom(
                        this@CalendarWidgetConfigureActivity,
                        widgetId,
                        choice.checkedRadioButtonId == bottom.id,
                    )
                    redraw(widgetId)
                    setResult(
                        RESULT_OK,
                        Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId),
                    )
                    finish()
                }
            })
        }
        val pad = (24 * resources.displayMetrics.density).toInt()
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad / 2, pad, pad / 3)
            addView(choice)
            addView(buttons)
        })
    }

    /** Has widget [widgetId] drawn again, as its receiver does on update. */
    private fun redraw(widgetId: Int) {
        sendBroadcast(
            Intent(this, CalendarWidgetReceiver::class.java)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId)),
        )
    }
}
