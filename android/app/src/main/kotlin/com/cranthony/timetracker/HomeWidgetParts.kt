package com.cranthony.timetracker

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.height
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics

/*
 * What the home screen calendar (CalendarWidget.kt) and goals
 * (GoalsWidget.kt) share: the round buttons in their headers, the goal
 * icon, and each widget's "title at the bottom" setting, with the
 * settings screen the launcher opens for it.
 */

/**
 * A round button in a widget's header, [icon] on it, doing [action]: a
 * 32dp circle in a 48dp tap target, as Android asks for, so two side by
 * side are each easy to hit. [compact], as the goals widget's is, a 24dp
 * circle in a 36dp by 28dp target, so its header takes well under half
 * as much of the widget, and the circle sits near its corner.
 */
@Composable
internal fun HeaderButton(icon: Int, label: String, action: Action, compact: Boolean = false) {
    Box(
        modifier = GlanceModifier
            .width(if (compact) 36.dp else 48.dp)
            .height(if (compact) 28.dp else 48.dp)
            .clickable(action)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = GlanceModifier
                .size(if (compact) 24.dp else 32.dp)
                .cornerRadius(16.dp)
                .background(GlanceTheme.colors.primary),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                provider = ImageProvider(icon),
                contentDescription = null,
                modifier = GlanceModifier.size(if (compact) 15.dp else 20.dp),
                colorFilter = ColorFilter.tint(GlanceTheme.colors.onPrimary),
            )
        }
    }
}

/**
 * The app's goal icon (GoalPainter, lib/widgets/goal_icon.dart), in white
 * to be tinted: a bullseye with an arrow stuck in the middle, come in
 * from the upper right, a gap cut round the arrow where it crosses the
 * rings. Drawn once, on a 24-unit square as the app's is.
 */
internal val goalIcon: Bitmap by lazy { drawGoalIcon() }

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

/**
 * Whether each widget of a kind has its title at its bottom, kept by the
 * widget's id in the preferences file [prefs]: the calendar's and the
 * goals' each in a file of their own.
 */
class TitleSetting(private val prefs: String) {
    private fun key(widgetId: Int) = "title_at_bottom_$widgetId"

    /** Whether widget [widgetId]'s header is at its bottom. */
    fun atBottom(context: Context, widgetId: Int): Boolean =
        context.getSharedPreferences(prefs, Context.MODE_PRIVATE)
            .getBoolean(key(widgetId), false)

    fun setAtBottom(context: Context, widgetId: Int, atBottom: Boolean) {
        context.getSharedPreferences(prefs, Context.MODE_PRIVATE).edit()
            .putBoolean(key(widgetId), atBottom)
            .apply()
    }

    /** Forgets the settings of the widgets [widgetIds], removed. */
    fun forget(context: Context, widgetIds: IntArray) {
        val edit = context.getSharedPreferences(prefs, Context.MODE_PRIVATE).edit()
        for (widgetId in widgetIds) edit.remove(key(widgetId))
        edit.apply()
    }
}

/** A widget's text size: how much bigger than its smallest. */
enum class TextSize(val scale: Float, val label: Int) {
    SMALL(1f, R.string.widget_text_small),
    MEDIUM(1.5f, R.string.widget_text_medium),
    LARGE(2f, R.string.widget_text_large),
}

/**
 * Each widget of a kind's text size, kept by the widget's id in the
 * preferences file [prefs], as [TitleSetting] keeps its title's place;
 * [TextSize.SMALL] until it's set.
 */
class TextSizeSetting(private val prefs: String) {
    private fun key(widgetId: Int) = "text_size_$widgetId"

    fun of(context: Context, widgetId: Int): TextSize {
        val name = context.getSharedPreferences(prefs, Context.MODE_PRIVATE)
            .getString(key(widgetId), null)
        return TextSize.values().firstOrNull { it.name == name } ?: TextSize.SMALL
    }

    fun set(context: Context, widgetId: Int, size: TextSize) {
        context.getSharedPreferences(prefs, Context.MODE_PRIVATE).edit()
            .putString(key(widgetId), size.name)
            .apply()
    }

    /** Forgets the settings of the widgets [widgetIds], removed. */
    fun forget(context: Context, widgetIds: IntArray) {
        val edit = context.getSharedPreferences(prefs, Context.MODE_PRIVATE).edit()
        for (widgetId in widgetIds) edit.remove(key(widgetId))
        edit.apply()
    }
}

/**
 * One home screen widget's settings: whether its title -- and the
 * buttons beside it -- is at its top or its bottom ([setting]), and,
 * for a widget with one ([textSize]), its text size. Android opens it
 * from the widget's settings (from Android 12, holding it down), and,
 * before that, as it's added. Done keeps the choices, for that widget
 * alone, and has [receiver] draw it again; backed out of, it's left as
 * it was. Each widget's own activity gives its [titleRes].
 */
abstract class WidgetConfigureActivity : Activity() {
    protected abstract val titleRes: Int
    protected abstract val setting: TitleSetting
    protected abstract val receiver: Class<out BroadcastReceiver>

    /** The widget's text size setting; null for a widget without one. */
    protected open val textSize: TextSizeSetting? = null

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
        setTitle(titleRes)

        val atBottom = setting.atBottom(this, widgetId)
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
        // The text size, for a widget with one: a button for each, the
        // one set checked.
        val sizeSetting = textSize
        val sizeButtons = if (sizeSetting == null) {
            null
        } else {
            TextSize.values().associateWith { size ->
                RadioButton(this).apply {
                    id = View.generateViewId()
                    setText(size.label)
                }
            }
        }
        val sizes = if (sizeSetting == null || sizeButtons == null) {
            null
        } else {
            RadioGroup(this).apply {
                for (button in sizeButtons.values) addView(button)
                check(sizeButtons.getValue(sizeSetting.of(this@WidgetConfigureActivity, widgetId)).id)
            }
        }
        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            addView(Button(this@WidgetConfigureActivity, null, android.R.attr.buttonBarButtonStyle).apply {
                setText(android.R.string.cancel)
                setOnClickListener { finish() }
            })
            addView(Button(this@WidgetConfigureActivity, null, android.R.attr.buttonBarButtonStyle).apply {
                setText(R.string.calendar_widget_settings_done)
                setOnClickListener {
                    setting.setAtBottom(
                        this@WidgetConfigureActivity,
                        widgetId,
                        choice.checkedRadioButtonId == bottom.id,
                    )
                    if (sizeSetting != null && sizes != null && sizeButtons != null) {
                        val picked = sizeButtons.entries
                            .firstOrNull { it.value.id == sizes.checkedRadioButtonId }?.key
                        if (picked != null) sizeSetting.set(this@WidgetConfigureActivity, widgetId, picked)
                    }
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
            if (sizes != null) {
                addView(TextView(this@WidgetConfigureActivity).apply {
                    setText(R.string.widget_text_size)
                    setPadding(0, pad / 2, 0, 0)
                })
                addView(sizes)
            }
            addView(buttons)
        })
    }

    /** Has widget [widgetId] drawn again, as its receiver does on update. */
    private fun redraw(widgetId: Int) {
        sendBroadcast(
            Intent(this, receiver)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId)),
        )
    }
}
