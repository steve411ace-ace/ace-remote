package vn.aceremote.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Step 27: home-screen widget 4x2 (AppWidgetProvider + RemoteViews, XML —
 * NOT Jetpack Glance: Glance would need `compose true` in
 * android/app/build.gradle, which is off-limits in this step because it
 * holds the fixed-signing-key config from step 20).
 *
 * Data comes from the home_widget SharedPreferences file
 * ("HomeWidgetPreferences") written by the Dart side (HomeWidgetSync);
 * the keys are the same names the Dart side uses (see
 * lib/home_widget_data.dart).
 *
 * ALL buttons use a launch intent into MainActivity — never a background
 * callback. home_widget's background isolate runs a bare FlutterEngine
 * without GeneratedPluginRegistrant, so SharedPreferences / HomeWidget
 * calls there throw MissingPluginException. A tap opens the app, the app
 * performs the action (toggle / switch / connect) and syncs the widget
 * back. Deep links: aceremote://connect/<id>, aceremote://toggle-trackpad,
 * aceremote://toggle-keyboard, aceremote://next-connection, aceremote://open.
 *
 * The widget background is a rounded-rect bitmap drawn here: RemoteViews
 * cannot set a shape drawable's color AND alpha together, and
 * setBackgroundColor would drop the rounded corners. Only the background
 * carries the opacity — text and buttons stay fully opaque.
 */
class AceRemoteWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.ace_remote_widget)
            bind(context, views, widgetData)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bind(context: Context, views: RemoteViews, data: SharedPreferences) {
        val name = data.getString("widget_name", "Ace Remote") ?: "Ace Remote"
        val address = data.getString("widget_address", "") ?: ""
        val status = data.getString("widget_status", "") ?: ""
        val trackpad = data.getBoolean("widget_trackpad", false)
        val keyboard = data.getBoolean("widget_keyboard", true)
        val hasNext = data.getBoolean("widget_has_next", false)
        val dark = data.getBoolean("widget_dark", true)
        val opacity = data.getInt("widget_opacity", 100).coerceIn(0, 100)
        val connectionId = data.getString("widget_connection_id", "") ?: ""
        val hasConnection = connectionId.isNotEmpty()

        // Colors: same palette as the app (step 23/24). Dark: card
        // 0xFF1E2E2C; light: white card. Subtitle grey 0xFFB0BEC5 (dark) /
        // 0xFF666666 (light).
        val bgColor = if (dark) 0xFF1E2E2C.toInt() else 0xFFFFFFFF.toInt()
        val titleColor = if (dark) Color.WHITE else 0xFF333333.toInt()
        val subtitleColor = if (dark) 0xFFB0BEC5.toInt() else 0xFF666666.toInt()
        val offPill = if (dark) R.drawable.widget_pill_off_dark
            else R.drawable.widget_pill_off_light
        val offText = if (dark) Color.WHITE else 0xFF333333.toInt()
        val alpha = (opacity * 255 / 100).coerceIn(0, 255)

        // Rounded background with the opacity applied (0% = invisible).
        views.setImageViewBitmap(
            R.id.widget_bg,
            roundedBackground(bgColor, alpha)
        )

        views.setTextViewText(R.id.widget_name, name)
        views.setTextColor(R.id.widget_name, titleColor)
        views.setTextViewText(R.id.widget_address, address)
        views.setTextColor(R.id.widget_address, subtitleColor)
        views.setTextViewText(R.id.widget_status, status)
        views.setTextColor(R.id.widget_status, subtitleColor)
        views.setViewVisibility(
            R.id.widget_status,
            if (status.isEmpty()) View.GONE else View.VISIBLE
        )

        // Trackpad / keyboard toggles: on = teal pill, off = grey pill.
        views.setInt(
            R.id.widget_btn_trackpad, "setBackgroundResource",
            if (trackpad) R.drawable.widget_pill_on else offPill
        )
        views.setTextColor(
            R.id.widget_btn_trackpad,
            if (trackpad) Color.WHITE else offText
        )
        views.setInt(
            R.id.widget_btn_keyboard, "setBackgroundResource",
            if (keyboard) R.drawable.widget_pill_on else offPill
        )
        views.setTextColor(
            R.id.widget_btn_keyboard,
            if (keyboard) Color.WHITE else offText
        )

        // Switch key: only when more than one connection is saved.
        views.setViewVisibility(
            R.id.widget_next,
            if (hasNext) View.VISIBLE else View.GONE
        )
        if (hasNext) {
            views.setInt(R.id.widget_next, "setBackgroundResource", offPill)
            views.setTextColor(R.id.widget_next, offText)
        }

        // No connection yet: hide the toggles, "Kết nối" becomes "Mở app".
        views.setViewVisibility(
            R.id.widget_btn_trackpad,
            if (hasConnection) View.VISIBLE else View.GONE
        )
        views.setViewVisibility(
            R.id.widget_btn_keyboard,
            if (hasConnection) View.VISIBLE else View.GONE
        )
        views.setTextViewText(
            R.id.widget_btn_connect,
            if (hasConnection) "Kết nối" else "Mở app"
        )

        // Launch intents (every tap opens the app; distinct URIs keep the
        // PendingIntents distinct). Tapping the info row connects too.
        val connectUri = if (hasConnection) {
            Uri.parse("aceremote://connect/$connectionId")
        } else {
            Uri.parse("aceremote://open")
        }
        views.setOnClickPendingIntent(
            R.id.widget_info,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, connectUri)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_connect,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, connectUri)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_trackpad,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java,
                Uri.parse("aceremote://toggle-trackpad")
            )
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_keyboard,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java,
                Uri.parse("aceremote://toggle-keyboard")
            )
        )
        if (hasNext) {
            views.setOnClickPendingIntent(
                R.id.widget_next,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("aceremote://next-connection")
                )
            )
        }
    }

    companion object {
        // Bitmap for the rounded background: 400x200 (~320 KB, well under
        // the RemoteViews parcel limit). Corner radius 48px ≈ 20dp at
        // ~2.5x density; the solid fill stretches cleanly to any size.
        private const val BG_WIDTH = 400
        private const val BG_HEIGHT = 200
        private const val BG_RADIUS = 48f

        /** Solid rounded-rect bitmap in [color] with the given [alpha]. */
        fun roundedBackground(color: Int, alpha: Int): Bitmap {
            val bitmap = Bitmap.createBitmap(BG_WIDTH, BG_HEIGHT, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color
                this.alpha = alpha
            }
            canvas.drawRoundRect(
                RectF(0f, 0f, BG_WIDTH.toFloat(), BG_HEIGHT.toFloat()),
                BG_RADIUS, BG_RADIUS, paint
            )
            return bitmap
        }
    }
}
