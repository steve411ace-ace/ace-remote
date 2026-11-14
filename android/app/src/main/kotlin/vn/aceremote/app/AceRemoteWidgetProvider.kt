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
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToInt

/**
 * Step 27: home-screen widget 4x2 (AppWidgetProvider + RemoteViews, XML —
 * NOT Jetpack Glance: Glance would need `compose true` in
 * android/app/build.gradle, which is off-limits because it holds the
 * fixed-signing-key config from step 20).
 *
 * Step 31: tapping ANYWHERE on the widget (except the 3 native buttons)
 * opens the app and connects — the launch PendingIntent is attached to
 * the widget ROOT, and taps on child views without their own handler
 * bubble up to it. (Step 29 attached the tap only to the info row, and
 * used a hand-rolled ACTION_VIEW intent: MainActivity has no ACTION_VIEW
 * + aceremote intent-filter, so the tap resolved to nothing, and the
 * home_widget plugin only delivers URIs for its own LAUNCH action — so
 * even a resolved VIEW tap would never reach _handleWidgetUri. The fix
 * uses the plugin's own HomeWidgetLaunchIntent.getActivity: an explicit
 * intent to MainActivity, LAUNCH action, URI as data — the exact
 * mechanism step 27 used, which worked.)
 * Corner radius is the Thuoc Vui standard (skill §3.3): 28dp, 1dp border.
 * The bitmap is drawn at the widget's REAL aspect ratio (from
 * AppWidgetManager options) so fitXY stretches it uniformly and the
 * corners stay circular — the old fixed 400x200 bitmap was stretched
 * non-uniformly (the Fold6 widget is ~2.5:1, not 2:1), which made the
 * corners elliptical ("bo không đều") and too round.
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
 * Tap anywhere else on the widget (root layout): launch intent
 * (aceremote://connect/<id>, or aceremote://open when nothing is
 * saved) — opens the app and connects. Step 31: the handler sits on
 * the ROOT view, not just the info row, so icon, name, address,
 * status, gaps and empty space all open the app; only the 3 buttons
 * above keep their own handlers.
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
            bind(context, appWidgetManager, appWidgetId, views, widgetData)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun bind(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        views: RemoteViews,
        data: SharedPreferences,
    ) {
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
        // fully opaque (step 27 mechanism, unchanged). Step 31: the bitmap
        // is drawn at the widget's real aspect ratio (28dp corners, 1dp
        // border — Thuoc Vui standard), so fitXY stretches it uniformly.
        views.setImageViewBitmap(
            R.id.widget_bg,
            roundedBackground(appWidgetManager, appWidgetId, bgColor, alpha, dark)
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

        // --- Tap anywhere (except the 3 native buttons) = open the app
        // and connect (step 31). The launch PendingIntent is attached to
        // the widget ROOT: taps on child views without their own handler
        // (icon tile, name, address, status, empty space, background)
        // bubble up to it, while the 2 pills and the switch key keep their
        // own broadcast handlers and never open the app. The old
        // ACTION_VIEW intent on widget_info is gone — see the class doc
        // for why it never opened the app. Uses the plugin's own launch
        // helper (explicit MainActivity + LAUNCH action + URI as data),
        // which also handles the Android 14+ background-activity-start
        // allowance; the plugin delivers the URI to Dart via
        // initiallyLaunchedFromHomeWidget / widgetClicked.
        val openUri = if (hasConnection) {
            Uri.parse("aceremote://connect/$connectionId")
        } else {
            Uri.parse("aceremote://open")
        }
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, openUri),
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

        // Background bitmap (step 31, Thuoc Vui standard): 28dp corner
        // radius, 1dp border. The bitmap is drawn at the widget's REAL
        // aspect ratio (from AppWidgetManager options) so the fitXY stretch
        // is uniform and the corners stay circular. The old fixed 400x200
        // bitmap was stretched non-uniformly — the Fold6 widget is ~2.5:1,
        // not 2:1 — so the corners came out elliptical ("bo không đều")
        // and too round (48px ≈ 38x31dp on screen). Bitmap width is fixed
        // at 480px (~380 KB max, well under the RemoteViews parcel limit);
        // the radius/border are computed in bitmap px from dp (density
        // cancels out: radiusPx = 28 * bitmapWidth / widgetWidthDp).
        private const val BG_WIDTH = 480
        private const val CORNER_RADIUS_DP = 28f
        private const val BORDER_WIDTH_DP = 1f
        private const val FALLBACK_WIDTH_DP = 250
        private const val FALLBACK_HEIGHT_DP = 110

        /** Solid rounded-rect bitmap in [color] with the given [alpha],
         * drawn at the widget's real aspect ratio with 28dp corners and a
         * 1dp border (Thuoc Vui standard). */
        fun roundedBackground(
            manager: AppWidgetManager,
            appWidgetId: Int,
            color: Int,
            alpha: Int,
            dark: Boolean,
        ): Bitmap {
            // Widget size in dp in the current orientation; fall back to
            // the declared 4x2 minimum when the options are unavailable.
            val options = try {
                manager.getAppWidgetOptions(appWidgetId)
            } catch (e: Exception) {
                null
            }
            var widthDp = options?.getInt(
                AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0) ?: 0
            var heightDp = options?.getInt(
                AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0) ?: 0
            if (widthDp <= 0 || heightDp <= 0) {
                widthDp = FALLBACK_WIDTH_DP
                heightDp = FALLBACK_HEIGHT_DP
            }
            // A 4x2 widget is always in this range; the clamp only guards
            // against bogus option values breaking the aspect ratio.
            val aspect = (widthDp.toFloat() / heightDp).coerceIn(1.5f, 3.5f)
            val bw = BG_WIDTH
            val bh = (bw / aspect).roundToInt().coerceIn(160, 320)
            // Bitmap px per dp; the on-screen radius is then exactly 28dp
            // and the border exactly 1dp, on any density or widget size.
            val pxPerDp = bw.toFloat() / widthDp
            val radius = CORNER_RADIUS_DP * pxPerDp
            val stroke = (BORDER_WIDTH_DP * pxPerDp).coerceAtLeast(1f)

            val bitmap = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val rect = RectF(0f, 0f, bw.toFloat(), bh.toFloat())
            val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color
                this.alpha = alpha
            }
            canvas.drawRoundRect(rect, radius, radius, fill)
            // 1dp border, drawn just inside the fill's edge so it is never
            // clipped. Subtle by design (white 12% on dark, black 10% on
            // light); its alpha is scaled by the same opacity, so a fully
            // transparent widget has no border either.
            val borderAlpha = ((if (dark) 31 else 26) * alpha) / 255
            val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = stroke
                this.color = if (dark) {
                    Color.argb(borderAlpha, 255, 255, 255)
                } else {
                    Color.argb(borderAlpha, 0, 0, 0)
                }
            }
            val inset = stroke / 2f
            val innerRadius = (radius - inset).coerceAtLeast(0f)
            canvas.drawRoundRect(
                RectF(inset, inset, bw - inset, bh - inset),
                innerRadius, innerRadius, border
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
            // Step 36: the click-keys setting ('showBoth'/'hideRight'/
            // 'hideBoth'). The widget never changes it, but it must be
            // carried through saveConnections — otherwise a widget toggle
            // would rewrite the JSON and drop the setting.
            val clickKeys: String,
            // Step 37: same for the trackpad-area setting.
            val trackpadArea: Boolean,
            // Step 48: same for the trackpad-sensitivity setting.
            val trackpadSensitivity: Double,
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
                            clickKeys = o.optString("clickKeys", "showBoth"),
                            trackpadArea = o.optBoolean("trackpadArea", false),
                            trackpadSensitivity = o.optDouble("trackpadSensitivity", 1.5),
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
                o.put("clickKeys", c.clickKeys)
                o.put("trackpadArea", c.trackpadArea)
                o.put("trackpadSensitivity", c.trackpadSensitivity)
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
