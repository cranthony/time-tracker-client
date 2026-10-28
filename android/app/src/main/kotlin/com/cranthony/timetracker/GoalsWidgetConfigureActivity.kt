package com.cranthony.timetracker

/**
 * One home screen goals widget's settings: whether its title -- "Goals",
 * and its goal button -- is at its top or its bottom; see
 * WidgetConfigureActivity.
 */
class GoalsWidgetConfigureActivity : WidgetConfigureActivity() {
    override val titleRes = R.string.goals_widget_settings_title
    override val setting = GoalsWidget.title
    override val receiver = GoalsWidgetReceiver::class.java
}
