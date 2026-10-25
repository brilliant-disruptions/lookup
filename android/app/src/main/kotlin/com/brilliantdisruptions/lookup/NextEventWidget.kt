package com.brilliantdisruptions.lookup

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: the next thing worth stepping outside for, with a live
 * countdown (Chronometer ticks on its own, no app wake-ups needed).
 * Data is written by lib/services/widget_service.dart via home_widget.
 */
class NextEventWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.next_event_widget)
            val title = widgetData.getString("next_title", null)
            val whenText = widgetData.getString("next_when", null)
            val direction = widgetData.getString("next_direction", null)
            val startMillis = widgetData.getLong("next_start_ms", 0L)

            views.setTextViewText(R.id.widget_title, title ?: "A quiet sky")
            views.setTextViewText(R.id.widget_when, whenText ?: "We'll tap you when something's up")
            views.setTextViewText(R.id.widget_direction, direction ?: "")

            val now = System.currentTimeMillis()
            if (startMillis > now && startMillis - now < 24 * 3600 * 1000L) {
                // Chronometer counts down to `base` in elapsedRealtime time.
                val base = SystemClock.elapsedRealtime() + (startMillis - now)
                views.setChronometerCountDown(R.id.widget_countdown, true)
                views.setChronometer(R.id.widget_countdown, base, null, true)
                views.setViewVisibility(R.id.widget_countdown, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_countdown, View.GONE)
            }

            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
