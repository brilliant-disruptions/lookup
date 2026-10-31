package com.brilliantdisruptions.lookup

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home-screen widget: the next thing worth stepping outside for, with its
 * "where to look" picture behind, its colour, which way to face and a live
 * countdown (the Chronometer ticks on its own, no app wake-ups needed).
 * Data is written by lib/services/widget_service.dart via home_widget.
 */
class NextEventWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // Dart ints arrive as Int or Long depending on size: read either.
        fun number(key: String): Long? = (widgetData.all[key] as? Number)?.toLong()

        val title = widgetData.getString("next_title", null)
        val whenText = widgetData.getString("next_when", null)
        val direction = widgetData.getString("next_direction", null)
        val kicker = widgetData.getString("next_kicker", null)
        val startMillis = number("next_start_ms") ?: 0L
        val tint = number("next_tint")?.toInt() ?: 0xFF5AA2FF.toInt()
        val art = loadArt(widgetData.getString("next_art", null))

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.next_event_widget)
            views.setTextViewText(R.id.widget_kicker, kicker ?: "LookUp")
            views.setTextColor(R.id.widget_kicker, tint)
            views.setTextViewText(R.id.widget_title, title ?: "A quiet sky")
            views.setTextViewText(R.id.widget_when, whenText ?: "We'll tap you when something's up")
            views.setTextViewText(R.id.widget_direction, direction ?: "")

            if (art != null) {
                views.setImageViewBitmap(R.id.widget_art, art)
                views.setViewVisibility(R.id.widget_art, View.VISIBLE)
                views.setViewVisibility(R.id.widget_scrim, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_art, View.GONE)
                views.setViewVisibility(R.id.widget_scrim, View.GONE)
            }

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

    /** The 1024×512 picture at half size: plenty for a widget, well inside RemoteViews' bitmap limit. */
    private fun loadArt(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        return try {
            val file = File(path)
            if (!file.exists()) null else BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = 2 })
        } catch (_: Throwable) {
            null
        }
    }
}
