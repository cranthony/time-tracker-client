package com.cranthony.timetracker

/**
 * One home screen calendar's settings: whether its title -- "Calendar",
 * and its buttons -- is at its top or its bottom; see
 * WidgetConfigureActivity.
 */
class CalendarWidgetConfigureActivity : WidgetConfigureActivity() {
    override val titleRes = R.string.calendar_widget_settings_title
    override val setting = CalendarWidget.title
    override val receiver = CalendarWidgetReceiver::class.java
}
