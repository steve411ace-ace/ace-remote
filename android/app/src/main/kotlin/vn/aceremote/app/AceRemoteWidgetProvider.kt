package vn.aceremote.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject

/**
 * Step 27: home-screen widget 4x2 (AppWidgetProvider + RemoteViews, XML —
 * NOT Jetpack Glance: Glance would need `compose true` in
 * android/app/build.gradle, which is off-limits because it holds the
 * fixed-signing-key config from step 20).
 *
 * Step 29: ALL widget buttons are handled NATIVE here, without opening the
 * app. Only tapping the connection info area opens the app (and connects).
 * The old "Connect" button is gone — the info area is the only way in.
 * The widget was also redesigned (Material 3, modern): an icon tile with a
 * real monitor vector icon, a circular swap button with a real vector icon
 * (no more "⇄" character, which some fonts render as a hollow box), and
 * toggle pills with icon + label.
 *
 * How the native actions work (verified against the real plugin sources,
 * shared_preferences_android 2.4.7 / shared_preferences 2.5.3):
 *
 * - Dart's `SharedPreferences` (legacy sync API, what the app uses) is
 *   served by LegacySharedPreferencesPlugin, which stores keys VERBATIM
 *   in the classic XML file "FlutterSharedPreferences". The Dart side
 *   prefixes every key with "flutter." before sending it, so the keys on
 *   disk are literally "flutter.rdp_connections",
 *   "flutter.ace_widget_current_id", "flutter.ace_remote_v1_theme",
 *   "flutter.ace_widget_opacity".
 * - The DataStore backend (FlutterSharedPreferences.preferences_pb) is
 *   only used by Dart's async SharedPreferences API, which this app does
 *   NOT use for its prefs. Kotlin must read/write the XML file above,
 *   NOT the DataStore file.
 * - Writes are per-key merges (SharedPreferences.Editor.apply()), so a
 *   native write never clobbers other keys. The app reads the new values
 *   the next time it starts (cold start loads from disk).
 * - ONE CAVEAT (Dart side, needs a small follow-up, not fixable from
 *   native code): Dart's SharedPreferences keeps an in-memory cache
 *   loaded at first getInstance(). If the app process is still alive in
 *   the background when the user toggles from the widget, the running app
 *   still sees the OLD values until it restarts or calls prefs.reload().
 *   The config on disk and the widget display are always correct; the
 *   fix is to call reload() before RdpConnectionStore.load() on resume /
 *   in the widget-action paths (lib/main.dart, lib/rdp_connections.dart).
 *
 * Buttons (all native, no app launch):
 * - Toggle trackpad: flips `trackpad` of the current connection.
 * - Toggle keyboard: flips `keyboard` of the current connection.
 * - Switch: cycles to the next saved connection (favorites first),
 *   wraps around, stores the new current id.
 * Info area tap: launch intent (aceremote://connect/<id>) — opens the app
 * and connects, exactly as in step 27.
 *
 * Each button gets a PendingIntent.getBroadcast with its own action.
 * onReceive intercepts those actions, updates the prefs + the widget
 * views immediately, and returns without calling super (so the app is
 * never launched). Every other broadcast falls through to
 * HomeWidgetProvider (update/enable/disable).
 */
class AceRemoteWidgetProvider : HomeWidgetProvider() {

    // ------------------------------------------------------------------
    // Native button handling
    // ------------------------------------------------------------------

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TOGGLE_TRACKPAD,
            ACTION_TOGGLE_KEYBOARD,
            ACTION_NEXT_CONNECTION -> {
                try {
                    handleNativeAction(context, intent.action!!)
                } catch (e: Exception) {
                    // A failed widget tap must never crash the receiver or
                    // open the app; the widget simply stays as it was.
                    Log.w(TAG, "Native widget action failed", e)
                }
                return
            }
            else -> super.onReceive(context, intent)
        }
    }

    /**
     * Applies one native button action and re-renders every widget instance
     * immediately, all without opening the app. Reads/writes the same
     * SharedPreferences file and keys the Dart app uses (see class doc).
     */
    private fun handleNativeAction(context: Context, action: String) {
        val prefs = appPrefs(context)
        val conns = loadConnections(prefs)
        if (conns.isEmpty()) return
        val ordered = conns.displayOrder()
        val storedId = prefs.getString(KEY_CURRENT_ID, null)
        val current = ordered.firstOrNull { it.id == storedId } ?: ordered.first()

        when (action) {
            ACTION_TOGGLE_TRACKPAD -> {
                val updated = current.copy(trackpad = !current.trackpad)
                saveConnections(prefs, conns.map { if (it.id == updated.id) updated else it })
                prefs.edit().putString(KEY_CURRENT_ID, updated.id).apply()
                mirrorDisplayState(context, updated, ordered.size > 1)
                Log.d(TAG, "Trackpad -> ${updated.trackpad} for ${updated.name}")
            }
            ACTION_TOGGLE_KEYBOARD -> {
                val updated = current.copy(keyboard = !current.keyboard)
                saveConnections(prefs, conns.map { if (it.id == updated.id) updated else it })
                prefs.edit().putString(KEY_CURRENT_ID, updated.id).apply()
                mirrorDisplayState(context, updated, ordered.size > 1)
                Log.d(TAG, "Keyboard -> ${updated.keyboard} for ${updated.name}")
            }
            ACTION_NEXT_CONNECTION -> {
                if (ordered.size < 2) return
                val idx = ordered.indexOfFirst { it.id == current.id }
                val next = ordered[(idx + 1) % ordered.size]
                prefs.edit().putString(KEY_CURRENT_ID, next.id).apply()
                mirrorDisplayState(context, next, true)
                Log.d(TAG, "Switched to ${next.name}")
            }
        }
        refreshAllWidgets(context)
    }

    /**
     * Mirrors the new display state into HomeWidgetPreferences (the file
     * bind() reads for the widget views), so the next onUpdate shows the
     * same state even before the app syncs again. Theme/opacity are left
     * alone — they are owned by the app's sync.
     */
    private fun mirrorDisplayState(context: Context, c: Conn, hasNext: Boolean) {
        widgetPrefs(context).edit()
            .putString("widget_name", c.name)
            .putString("widget_address", "${c.host}:${c.port}")
            .putString("widget_status", statusText(c))
            .putBoolean("widget_trackpad", c.trackpad)
            .putBoolean("widget_keyboard", c.keyboard)
            .putBoolean("widget_has_next", hasNext)
            .putString("widget_connection_id", c.id)
            .apply()
    }

    /** Re-renders every widget instance right now. */
    private fun refreshAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, AceRemoteWidgetProvider::class.java)
        )
        for (id in ids) onUpdate(context, manager, intArrayOf(id))
    }

    private fun broadcastIntent(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, AceRemoteWidgetProvider::class.java).apply {
            this.action = action
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // ------------------------------------------------------------------
    // Widget rendering (step 27, redesigned in step 29)
    // ------------------------------------------------------------------

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.ace_remote_widget)
            bind(context, views, widgetData)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun bind(context: Context, views: RemoteViews, data: SharedPreferences) {
        val name = data.getString("widget_name", null)
        val address = data.getString("widget_address", null)
        val status = data.getString("widget_status", null)
        val trackpad = data.getBoolean("widget_trackpad", false)
        val keyboard = data.getBoolean("widget_keyboard", true)
        val hasNext = data.getBoolean("widget_has_next", false)
        val connectionId = data.getString("widget_connection_id", null)
        val dark = data.getBoolean("widget_dark", true)
        val opacity = data.getInt("widget_opacity", 100).coerceIn(0, 100)
        val hasConnection = !connectionId.isNullOrEmpty()

        // Colors: same palette as the app (steps 23/24).
        val bgColor = if (dark) 0xFF1E2E2C.toInt() else 0xFFFFFFFF.toInt()
        val titleColor = if (dark) Color.WHITE else 0xFF333333.toInt()
        val subtitleColor = if (dark) 0xFFB0BEC5.toInt() else 0xFF666666.toInt()
        val offPill = if (dark) R.drawable.widget_pill_off_dark
            else R.drawable.widget_pill_off_light
        val offText = if (dark) Color.WHITE else 0xFF333333.toInt()
        val alpha = (opacity * 255 / 100).coerceIn(0, 255)

        // Rounded background with the opacity applied (0% = invisible).
        // Only the background carries the opacity — text and buttons stay
        // fully opaque (step 27 mechanism, unchanged).
        views.setImageViewBitmap(
            R.id.widget_bg,
            roundedBackground(bgColor, alpha)
        )

        // --- Info area (tap = open the app and connect) ---
        if (!hasConnection) {
            views.setTextViewText(R.id.widget_name, "Chưa có kết nối")
            views.setTextViewText(R.id.widget_address, "Mở app để thêm kết nối")
            views.setViewVisibility(R.id.widget_status, View.GONE)
            views.setViewVisibility(R.id.widget_next, View.GONE)
            views.setViewVisibility(R.id.widget_actions, View.GONE)
        } else {
            views.setTextViewText(R.id.widget_name, name ?: "Ace Remote")
            views.setTextViewText(R.id.widget_address, address ?: "")
            if (status.isNullOrEmpty()) {
                views.setViewVisibility(R.id.widget_status, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_status, View.VISIBLE)
                views.setTextViewText(R.id.widget_status, status)
            }
            views.setViewVisibility(
                R.id.widget_next,
                if (hasNext) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(R.id.widget_actions, View.VISIBLE)
        }
        views.setTextColor(R.id.widget_name, titleColor)
        views.setTextColor(R.id.widget_address, subtitleColor)
        views.setTextColor(R.id.widget_status, subtitleColor)

        // Switch button: subtle circle + real swap vector icon (step 29:
        // no more "⇄" character, which some fonts render as a hollow box).
        views.setInt(
            R.id.widget_next, "setBackgroundResource",
            if (dark) R.drawable.widget_circle_off_dark
            else R.drawable.widget_circle_off_light
        )
        views.setInt(R.id.widget_next, "setColorFilter", offText)

        // --- Toggle pills: NATIVE broadcast intents, no app launch ---
        views.setOnClickPendingIntent(
            R.id.widget_btn_trackpad,
            broadcastIntent(context, ACTION_TOGGLE_TRACKPAD, 101),
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_keyboard,
            broadcastIntent(context, ACTION_TOGGLE_KEYBOARD, 102),
        )
        views.setOnClickPendingIntent(
            R.id.widget_next,
            broadcastIntent(context, ACTION_NEXT_CONNECTION, 103),
        )

        // Pill states: ON = teal with white icon + label; OFF = grey with
        // muted icon + label.
        applyPill(views, R.id.widget_btn_trackpad,
            R.id.widget_btn_trackpad_icon, R.id.widget_btn_trackpad_label,
            trackpad, offPill, offText)
        applyPill(views, R.id.widget_btn_keyboard,
            R.id.widget_btn_keyboard_icon, R.id.widget_btn_keyboard_label,
            keyboard, offPill, offText)

        // --- Info area tap: the ONLY way to open the app from the widget ---
        val infoUri = if (hasConnection) {
            Uri.parse("aceremote://connect/$connectionId")
        } else {
            Uri.parse("aceremote://open")
        }
        val infoIntent = Intent(Intent.ACTION_VIEW, infoUri).apply {
            `package` = context.packageName
        }
        views.setOnClickPendingIntent(
            R.id.widget_info,
            PendingIntent.getActivity(
                context, 100, infoIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
    }

    /** One toggle pill: background + icon tint + label color for ON/OFF. */
    private fun applyPill(
        views: RemoteViews,
        pillId: Int,
        iconId: Int,
        labelId: Int,
        on: Boolean,
        offPill: Int,
        offText: Int,
    ) {
        views.setInt(pillId, "setBackgroundResource",
            if (on) R.drawable.widget_pill_on else offPill)
        views.setInt(iconId, "setColorFilter", if (on) Color.WHITE else offText)
        views.setTextColor(labelId, if (on) Color.WHITE else offText)
    }

    companion object {
        private const val TAG = "AceWidget"

        // --- App prefs (classic XML file, keys with the "flutter." prefix
        // the Dart side adds; see the class doc) ---
        private const val APP_PREFS_FILE = "FlutterSharedPreferences"
        private const val KEY_CONNECTIONS = "flutter.rdp_connections"
        private const val KEY_CURRENT_ID = "flutter.ace_widget_current_id"
        private const val KEY_THEME = "flutter.ace_remote_v1_theme"
        private const val KEY_OPACITY = "flutter.ace_widget_opacity"

        // --- Widget display prefs (home_widget plugin's own file) ---
        private const val WIDGET_PREFS_FILE = "HomeWidgetPreferences"

        // --- Native button actions (explicit broadcast to this receiver) ---
        const val ACTION_TOGGLE_TRACKPAD =
            "vn.aceremote.app.widget.ACTION_TOGGLE_TRACKPAD"
        const val ACTION_TOGGLE_KEYBOARD =
            "vn.aceremote.app.widget.ACTION_TOGGLE_KEYBOARD"
        const val ACTION_NEXT_CONNECTION =
            "vn.aceremote.app.widget.ACTION_NEXT_CONNECTION"

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

        private data class Conn(
            val id: String,
            val name: String,
            val host: String,
            val port: Int,
            val trackpad: Boolean,
            val keyboard: Boolean,
            val favorite: Boolean,
        )

        /** Display order: favorites first, insertion order otherwise. */
        private fun List<Conn>.displayOrder(): List<Conn> =
            sortedWith(compareByDescending { it.favorite })

        private fun appPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(APP_PREFS_FILE, Context.MODE_PRIVATE)

        private fun widgetPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(WIDGET_PREFS_FILE, Context.MODE_PRIVATE)

        /** Parses the stored JSON list; returns insertion order, [] on error. */
        private fun loadConnections(prefs: SharedPreferences): List<Conn> {
            val raw = prefs.getString(KEY_CONNECTIONS, null) ?: return emptyList()
            return try {
                val arr = JSONArray(raw)
                val out = ArrayList<Conn>(arr.length())
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val id = o.optString("id", "")
                    if (id.isEmpty()) continue
                    out.add(
                        Conn(
                            id = id,
                            name = o.optString("name", id),
                            host = o.optString("host", ""),
                            port = o.optInt("port", 3389),
                            trackpad = o.optBoolean("trackpad", false),
                            keyboard = o.optBoolean("keyboard", true),
                            favorite = o.optBoolean("favorite", false),
                        )
                    )
                }
                out
            } catch (e: Exception) {
                Log.w(TAG, "Cannot parse $KEY_CONNECTIONS", e)
                emptyList()
            }
        }

        /** Serializes back in the same insertion order the app wrote. */
        private fun saveConnections(prefs: SharedPreferences, conns: List<Conn>) {
            val arr = JSONArray()
            for (c in conns) {
                val o = JSONObject()
                o.put("id", c.id)
                o.put("name", c.name)
                o.put("host", c.host)
                o.put("port", c.port)
                o.put("trackpad", c.trackpad)
                o.put("keyboard", c.keyboard)
                o.put("favorite", c.favorite)
                arr.put(o)
            }
            prefs.edit().putString(KEY_CONNECTIONS, arr.toString()).apply()
        }

        /** Same status line the Dart sync writes (see lib/home_widget_data.dart). */
        private fun statusText(c: Conn): String {
            val mode = if (c.trackpad) "Trackpad" else "Chạm"
            val kb = if (c.keyboard) "" else " • Ẩn bàn phím"
            return "Đã lưu • $mode$kb"
        }
    }
}
