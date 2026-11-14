package vn.aceremote.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.BitmapDrawable
import android.os.Handler
import android.os.SystemClock
import android.util.Log
import android.os.Looper
import android.view.InputDevice
import android.view.MotionEvent
import android.view.PointerIcon
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import com.freerdp.freerdpcore.application.GlobalApp
import com.freerdp.freerdpcore.application.SessionState
import com.freerdp.freerdpcore.domain.BookmarkBase
import com.freerdp.freerdpcore.services.LibFreeRDP
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class RdpPlugin : FlutterPlugin {
    // Step 36 removed the mouse-detection channel ('vn.aceremote.app/input'
    // + InputDeviceListener): the Left/Right keys are manual now (An: "Thay
    // hẳn, chỉnh tay thôi"), so nothing needs to know whether a mouse is
    // attached. The step 35 isExternal fix went with it — it never shipped.
    // Mouse driving itself (mouseMove/mouseButton channels below) and the
    // SOURCE_MOUSE ignore in onTouch stay: a real mouse still drives the
    // PC cursor, and its clicks never fire twice.
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding.platformViewRegistry.registerViewFactory("vn.aceremote.app/rdp", RdpFactory(binding))
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    }
}

/** LibFreeRDP has one process listener. Keep GlobalApp notifications and route by handle. */
private object RdpEvents : LibFreeRDP.EventListener {
    val sessions = ConcurrentHashMap<Long, LibFreeRDP.EventListener>()
    private var upstream: LibFreeRDP.EventListener? = null
    @Synchronized fun install(context: Context) {
        if (upstream == null) {
            upstream = (context.applicationContext as? LibFreeRDP.EventListener)
                ?: throw IllegalStateException("Application must be GlobalApp")
            LibFreeRDP.setEventListener(this)
        }
    }
    override fun OnPreConnect(instance: Long) { upstream?.OnPreConnect(instance); sessions[instance]?.OnPreConnect(instance) }
    override fun OnConnectionSuccess(instance: Long) { upstream?.OnConnectionSuccess(instance); sessions[instance]?.OnConnectionSuccess(instance) }
    override fun OnConnectionFailure(instance: Long) { upstream?.OnConnectionFailure(instance); sessions[instance]?.OnConnectionFailure(instance) }
    override fun OnDisconnecting(instance: Long) { upstream?.OnDisconnecting(instance); sessions[instance]?.OnDisconnecting(instance) }
    override fun OnDisconnected(instance: Long) { upstream?.OnDisconnected(instance); sessions[instance]?.OnDisconnected(instance) }
}

private class RdpFactory(private val binding: FlutterPlugin.FlutterPluginBinding) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = RdpView(context, viewId, binding)
}

private class RdpView(private val context: Context, id: Int, binding: FlutterPlugin.FlutterPluginBinding) :
    PlatformView, SurfaceHolder.Callback {
    private val surface = SurfaceView(context)
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private val channel = MethodChannel(binding.binaryMessenger, "vn.aceremote.app/rdp/$id")
    private var disposed = false
    private var surfaceReady = false
    // SurfaceHolder dimensions are physical pixels, already including density.
    private var widthPx = 0
    private var heightPx = 0
    private var resizeGeneration = 0
    private var resizeFailure: String? = null
    private val resizeTask = Runnable { synchronized(lock) { attempt?.resize(resizeGeneration, 0) } }
    private var state = "idle"
    private var error: String? = null
    private var authAttempted = false
    private var attempt: Attempt? = null
    private var bitmap: Bitmap? = null
    private var loadError: String? = null
    private val h264 = try { LibFreeRDP.hasH264Support() } catch (_: LinkageError) {
        loadError = "Không tải được FreeRDP"; false
    } catch (_: RuntimeException) { loadError = "Không tải được FreeRDP"; false }

    // Mouse.java:20–30. Do not use Mouse helpers: they read swap/invert
    // ApplicationSettingsActivity preferences that Ace does not provide.
    private val PTRFLAGS_LBUTTON = 0x1000
    private val PTRFLAGS_RBUTTON = 0x2000
    private val PTRFLAGS_MBUTTON = 0x4000
    private val PTRFLAGS_DOWN = 0x8000
    private val PTRFLAGS_MOVE = 0x0800
    private val PTRFLAGS_WHEEL = 0x0200
    private val PTRFLAGS_WHEEL_NEGATIVE = 0x0100
    private val PTRFLAGS_HWHEEL = 0x0400
    private val WHEEL_DELTA = 120
    private var bitmapWidth = 0
    private var bitmapHeight = 0
    private var lastX = 0
    private var lastY = 0
    private var touched = false
    // Remote cursor shape from FreeRDP (OnPointerSet). The pointer is not
    // part of the framebuffer, so render() draws it as an overlay at the
    // last known cursor position; without a shape it draws a fallback arrow.
    private var pointerBitmap: Bitmap? = null
    private var pointerHotX = 0
    private var pointerHotY = 0
    // Connect timing (step 23, item 5): elapsed ms from the 'connect' call
    // to each phase, logged so a slow reconnect can be pinpointed in logcat.
    // connectPhase is also sent to Dart (snapshot) for the progress display.
    private var connectStartedAt = 0L
    private var connectPhase = ""
    private var firstFrameLogged = false
    // Relative (trackpad) touch: the finger position never moves the cursor.
    // Drag moves the cursor by the finger delta; tap clicks at the cursor.
    private var trackpadMode = false
    private var trackpadCursorX = 0f
    private var trackpadCursorY = 0f
    private var trackpadLastX = 0f
    private var trackpadLastY = 0f
    // Step 47 (An): clipboard sync, text only. FreeRDP's /clipboard flag
    // is already on — LibFreeRDP.setConnectionInfo adds it unconditionally
    // — so the native cliprdr channel is up; this app only had empty
    // stubs for the callbacks. PC -> phone: OnRemoteClipboardChanged
    // writes the Android clipboard. Phone -> PC: this listener sends the
    // local text to the PC. lastRemoteText stops our own echo from
    // bouncing back to the PC (the server only notifies on change, so a
    // single guarded bounce is the worst case anyway).
    private val clipboardManager =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private var lastRemoteText: String? = null
    private val clipboardListener =
        ClipboardManager.OnPrimaryClipChangedListener {
            val text = localClipboardText()
                ?: return@OnPrimaryClipChangedListener
            synchronized(lock) {
                if (disposed || state != "connected") return@OnPrimaryClipChangedListener
                if (text == lastRemoteText) return@OnPrimaryClipChangedListener
                val h = attempt?.handle ?: 0L
                if (h == 0L) return@OnPrimaryClipChangedListener
                LibFreeRDP.sendClipboardData(h, text)
                Log.d("AceRdp", "clipboard: phone -> PC (${text.length} chars)")
            }
        }
    private fun localClipboardText(): String? {
        val clip = clipboardManager.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        return clip.getItemAt(0).text?.toString()?.takeIf { it.isNotEmpty() }
    }
    // Push the phone's current clipboard to the PC once, on connect
    // (same as aFreeRDP's getPrimaryClipManually): whatever was copied
    // before connecting is already there to paste.
    private fun pushLocalClipboard() {
        val text = localClipboardText() ?: return
        synchronized(lock) {
            if (disposed || state != "connected") return
            if (text == lastRemoteText) return
            val h = attempt?.handle ?: 0L
            if (h == 0L) return
            LibFreeRDP.sendClipboardData(h, text)
            Log.d("AceRdp", "clipboard: phone -> PC on connect (${text.length} chars)")
        }
    }
    private var trackpadMoved = false
    // Cursor moves 1.5x the finger delta (in framebuffer pixels): fast
    // enough to cross the screen with a short drag, slow enough to aim.
    // Step 48: relative-move multiplier, per connection (0.5–3.0, default
    // 1.5 — the value step 19 hard-coded here). Set from the Dart 'mode'
    // channel call together with the trackpad flag.
    private var trackpadSensitivity = 1.5f
    private class PendingMove(val owner: Attempt, var x: Int, var y: Int)
    private var lastMovePending: PendingMove? = null
    private var touchOwner: Attempt? = null
    private var downX = 0f
    private var downY = 0f
    private var downTime = 0L
    private var leftHeld = false
    private var rightHandled = false
    private var scrollMode = false
    private var scrollY = 0f
    private var scrollAccum = 0f
    private var twoFingerTravel = 0f
    private var twoFingerX = 0f
    private var twoFingerY = 0f
    private var twoFingerTap = false
    private val longPress = Runnable { synchronized(lock) {
        val a = touchOwner
        if (a != null && inputAttempt() === a && surfaceReady && !leftHeld && !scrollMode) {
            rightHandled = true
            clickAt(a, PTRFLAGS_RBUTTON)
        }
    } }

    // All submission and execution checks hold lock, and retain the attempt
    // identity so queued input can never leak into a replacement session.
    private fun inputAttempt(): Attempt? = attempt?.takeIf {
        !disposed && !it.stopping && !it.terminal && it.handle != 0L && it.connected && state == "connected"
    }
    private fun keyInput(vk: Int, down: Boolean) = synchronized(lock) {
        val a = inputAttempt() ?: return@synchronized
        lastMovePending = null
        executor.execute { synchronized(lock) {
            if (inputAttempt() === a) LibFreeRDP.sendKeyEvent(a.handle, vk, down)
        } }
    }
    private fun cursorInput(a: Attempt, x: Int, y: Int, flags: Int) {
        if (inputAttempt() !== a || !surfaceReady) return
        if (flags == PTRFLAGS_MOVE) {
            // The cursor overlay is drawn in render(); re-render so the
            // cursor visibly follows every move (draw() is debounced, so
            // rapid moves collapse to one render per frame).
            draw()
            lastMovePending?.takeIf { it.owner === a }?.let { it.x = x; it.y = y; return }
            val move = PendingMove(a, x, y)
            lastMovePending = move
            executor.execute { synchronized(lock) {
                if (lastMovePending === move) lastMovePending = null
                if (inputAttempt() === a && surfaceReady)
                    LibFreeRDP.sendCursorEvent(a.handle, move.x, move.y, PTRFLAGS_MOVE)
            } }
        } else {
            // A button/wheel is an ordering barrier for move coalescing.
            lastMovePending = null
            executor.execute { synchronized(lock) {
                if (inputAttempt() === a && surfaceReady) LibFreeRDP.sendCursorEvent(a.handle, x, y, flags)
            } }
        }
    }
    // Relative cursor move shared by the top-half trackpad touch and the
    // bottom-half trackpad ('moveRelative' channel call). Deltas arrive in
    // surface physical pixels; convert to framebuffer pixels with the
    // aspect-fit scale and the trackpad sensitivity. A float accumulator
    // avoids rounding drift from per-event truncation to Int.
    private fun moveCursorRelative(a: Attempt, dxSurfacePx: Float, dySurfacePx: Float) {
        if (bitmap == null || !surfaceReady) return
        val scale = minOf(widthPx.toFloat() / bitmapWidth, heightPx.toFloat() / bitmapHeight)
        if (scale <= 0f) return
        trackpadCursorX = (trackpadCursorX + dxSurfacePx / scale * trackpadSensitivity)
            .coerceIn(0f, (bitmapWidth - 1).toFloat())
        trackpadCursorY = (trackpadCursorY + dySurfacePx / scale * trackpadSensitivity)
            .coerceIn(0f, (bitmapHeight - 1).toFloat())
        lastX = trackpadCursorX.toInt(); lastY = trackpadCursorY.toInt()
        cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
    }
    // Step 34: surface physical pixels -> framebuffer pixels with the same
    // aspect-fit mapping onTouch uses (letterbox excluded). Null = the point
    // is not on the remote desktop (letterbox) or there is no frame yet.
    private fun surfaceToFramebuffer(xPx: Float, yPx: Float): Pair<Int, Int>? {
        if (bitmap == null) return null
        val scale = minOf(widthPx.toFloat() / bitmapWidth, heightPx.toFloat() / bitmapHeight)
        if (scale <= 0f) return null
        val x = (xPx - (widthPx - bitmapWidth * scale) / 2) / scale
        val y = (yPx - (heightPx - bitmapHeight * scale) / 2) / scale
        if (x < 0 || y < 0 || x >= bitmapWidth || y >= bitmapHeight) return null
        return x.toInt() to y.toInt()
    }

    private fun clickAt(a: Attempt, button: Int) {
        if (bitmap == null) return
        cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
        cursorInput(a, lastX, lastY, button or PTRFLAGS_DOWN)
        cursorInput(a, lastX, lastY, button)
    }
    private fun resetTouch(release: Boolean = true) {
        main.removeCallbacks(longPress)
        if (release && leftHeld) touchOwner?.let { cursorInput(it, lastX, lastY, PTRFLAGS_LBUTTON) }
        touchOwner = null; leftHeld = false; rightHandled = false
        scrollMode = false; scrollAccum = 0f; twoFingerTap = false; twoFingerTravel = 0f
        trackpadMoved = false
        lastMovePending = null
    }
    // Relative (trackpad) touch on the remote screen. Unlike absolute touch,
    // the finger position never moves the cursor: drag moves the cursor by
    // the finger delta (no button held), a quick tap clicks left AT THE
    // CURSOR, a two-finger tap clicks right at the cursor, and a two-finger
    // drag scrolls. Long-press still right-clicks, as in absolute mode.
    // Touches in the letterbox still work here (the whole surface is the
    // trackpad), so there is no bounds check. Called with lock held.
    private fun onTouchTrackpad(event: MotionEvent): Boolean {
        val a = inputAttempt()
        if (a == null || bitmap == null || !surfaceReady) {
            resetTouch(false)
            return false
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                resetTouch()
                touchOwner = a; downX = event.x; downY = event.y; downTime = event.eventTime
                trackpadLastX = event.x; trackpadLastY = event.y; trackpadMoved = false
                trackpadCursorX = lastX.toFloat(); trackpadCursorY = lastY.toFloat()
                cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
                main.postDelayed(longPress, 500)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                if (touchOwner === a && event.pointerCount >= 2) {
                    main.removeCallbacks(longPress)
                    if (leftHeld) cursorInput(a, lastX, lastY, PTRFLAGS_LBUTTON)
                    twoFingerTap = !scrollMode && !leftHeld && !rightHandled && event.pointerCount == 2
                    leftHeld = false; scrollMode = true
                    twoFingerX = (event.getX(0) + event.getX(1)) / 2
                    twoFingerY = (event.getY(0) + event.getY(1)) / 2
                    scrollY = (event.getY(0) + event.getY(1)) / 2; scrollAccum = 0f
                }
            }
            MotionEvent.ACTION_MOVE -> if (touchOwner === a) {
                if (scrollMode) {
                    if (event.pointerCount >= 2) {
                        val centerY = (event.getY(0) + event.getY(1)) / 2
                        val centerX = (event.getX(0) + event.getX(1)) / 2
                        twoFingerTravel += kotlin.math.hypot(centerX - twoFingerX, centerY - twoFingerY)
                        twoFingerX = centerX; twoFingerY = centerY
                        scrollAccum += centerY - scrollY; scrollY = centerY
                        while (kotlin.math.abs(scrollAccum) >= 48f) {
                            val down = scrollAccum > 0
                            val amount = if (down) -WHEEL_DELTA else WHEEL_DELTA
                            cursorInput(a, lastX, lastY, PTRFLAGS_WHEEL or
                                (if (down) PTRFLAGS_WHEEL_NEGATIVE else 0) or (amount and 0xFF))
                            scrollAccum += if (down) -48f else 48f
                        }
                    }
                } else if (!rightHandled) {
                    val dx = event.x - trackpadLastX
                    val dy = event.y - trackpadLastY
                    trackpadLastX = event.x; trackpadLastY = event.y
                    if (kotlin.math.hypot(event.x - downX, event.y - downY) > 12f) {
                        main.removeCallbacks(longPress)
                        trackpadMoved = true
                    }
                    moveCursorRelative(a, dx, dy)
                }
            }
            MotionEvent.ACTION_UP -> {
                if (touchOwner === a) {
                    if (leftHeld) cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
                    else if (!scrollMode && !rightHandled && !trackpadMoved &&
                        event.eventTime - downTime < 500)
                        clickAt(a, PTRFLAGS_LBUTTON)
                }
                resetTouch()
            }
            MotionEvent.ACTION_CANCEL -> resetTouch()
            // Stay in scroll mode until ACTION_UP, including the one-finger tail.
            MotionEvent.ACTION_POINTER_UP -> {
                main.removeCallbacks(longPress)
                if (touchOwner === a && twoFingerTap && event.pointerCount == 2) {
                    val centerX = (event.getX(0) + event.getX(1)) / 2
                    val centerY = (event.getY(0) + event.getY(1)) / 2
                    twoFingerTravel += kotlin.math.hypot(centerX - twoFingerX, centerY - twoFingerY)
                    // Right-click at the cursor, not at the finger midpoint.
                    if (event.eventTime - downTime < 500 && twoFingerTravel < 48f &&
                        kotlin.math.abs(scrollAccum) < 48f) {
                        clickAt(a, PTRFLAGS_RBUTTON)
                    }
                }
                twoFingerTap = false
            }
        }
        return true
    }
    private fun onTouch(event: MotionEvent): Boolean = synchronized(lock) {
        // Step 34: a physical mouse is owned by the Dart mouse layer
        // (absolute moves, button down/up, wheel through the channel). The
        // touch path must not also treat its clicks as finger taps, or
        // every click would fire twice.
        if (event.isFromSource(InputDevice.SOURCE_MOUSE)) return@synchronized false
        val a = inputAttempt()
        if (a == null || bitmap == null || !surfaceReady) {
            resetTouch(false)
            return@synchronized false
        }
        if (trackpadMode) return@synchronized onTouchTrackpad(event)
        val scale = minOf(widthPx.toFloat() / bitmapWidth, heightPx.toFloat() / bitmapHeight)
        if (scale <= 0f) return@synchronized true
        val x = (event.x - (widthPx - bitmapWidth * scale) / 2) / scale
        val y = (event.y - (heightPx - bitmapHeight * scale) / 2) / scale
        if (x < 0 || y < 0 || x >= bitmapWidth || y >= bitmapHeight) {
            // Letterbox is not a framebuffer point: swallow without sending.
            // Cancel the timer so a long press cannot fire while outside.
            resetTouch()
            return@synchronized true
        }
        if (event.pointerCount >= 2) {
            for (i in 0 until event.pointerCount) {
                val px = (event.getX(i) - (widthPx - bitmapWidth * scale) / 2) / scale
                val py = (event.getY(i) - (heightPx - bitmapHeight * scale) / 2) / scale
                if (px < 0 || py < 0 || px >= bitmapWidth || py >= bitmapHeight) {
                    resetTouch()
                    return@synchronized true
                }
            }
        }
        lastX = x.toInt(); lastY = y.toInt(); touched = true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                resetTouch()
                touchOwner = a; downX = event.x; downY = event.y; downTime = event.eventTime
                cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
                main.postDelayed(longPress, 500)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                if (touchOwner === a && event.pointerCount >= 2) {
                    main.removeCallbacks(longPress)
                    if (leftHeld) cursorInput(a, lastX, lastY, PTRFLAGS_LBUTTON)
                    twoFingerTap = !scrollMode && !leftHeld && !rightHandled && event.pointerCount == 2
                    leftHeld = false; scrollMode = true
                    twoFingerX = (event.getX(0) + event.getX(1)) / 2
                    twoFingerY = (event.getY(0) + event.getY(1)) / 2
                    scrollY = (event.getY(0) + event.getY(1)) / 2; scrollAccum = 0f
                }
            }
            MotionEvent.ACTION_MOVE -> if (touchOwner === a) {
                if (scrollMode) {
                    if (event.pointerCount >= 2) {
                        val centerY = (event.getY(0) + event.getY(1)) / 2
                        val centerX = (event.getX(0) + event.getX(1)) / 2
                        twoFingerTravel += kotlin.math.hypot(centerX - twoFingerX, centerY - twoFingerY)
                        twoFingerX = centerX; twoFingerY = centerY
                        scrollAccum += centerY - scrollY; scrollY = centerY
                        while (kotlin.math.abs(scrollAccum) >= 48f) {
                            val down = scrollAccum > 0
                            val amount = if (down) -WHEEL_DELTA else WHEEL_DELTA
                            cursorInput(a, lastX, lastY, PTRFLAGS_WHEEL or
                                (if (down) PTRFLAGS_WHEEL_NEGATIVE else 0) or (amount and 0xFF))
                            scrollAccum += if (down) -48f else 48f
                        }
                    }
                } else if (!rightHandled) {
                    val distance = kotlin.math.hypot(event.x - downX, event.y - downY)
                    if (distance > 12f && !leftHeld) {
                        main.removeCallbacks(longPress)
                        cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
                        cursorInput(a, lastX, lastY, PTRFLAGS_LBUTTON or PTRFLAGS_DOWN)
                        leftHeld = true
                    } else if (leftHeld) cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
                }
            }
            MotionEvent.ACTION_UP -> {
                if (touchOwner === a) {
                    if (leftHeld) cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
                    else if (!scrollMode && !rightHandled) {
                        val distance = kotlin.math.hypot(event.x - downX, event.y - downY)
                        if (distance < 12f && event.eventTime - downTime < 500)
                            clickAt(a, PTRFLAGS_LBUTTON)
                        else if (distance <= 12f && event.eventTime - downTime >= 500)
                            clickAt(a, PTRFLAGS_RBUTTON)
                    }
                }
                resetTouch()
            }
            MotionEvent.ACTION_CANCEL -> resetTouch()
            // Stay in scroll mode until ACTION_UP, including the one-finger tail.
            MotionEvent.ACTION_POINTER_UP -> {
                main.removeCallbacks(longPress)
                if (touchOwner === a && twoFingerTap && event.pointerCount == 2) {
                    val centerX = (event.getX(0) + event.getX(1)) / 2
                    val centerY = (event.getY(0) + event.getY(1)) / 2
                    twoFingerTravel += kotlin.math.hypot(centerX - twoFingerX, centerY - twoFingerY)
                    val midX = (centerX - (widthPx - bitmapWidth * scale) / 2) / scale
                    val midY = (centerY - (heightPx - bitmapHeight * scale) / 2) / scale
                    if (event.eventTime - downTime < 500 && twoFingerTravel < 48f &&
                        kotlin.math.abs(scrollAccum) < 48f && midX >= 0 && midY >= 0 &&
                        midX < bitmapWidth && midY < bitmapHeight) {
                        lastX = midX.toInt(); lastY = midY.toInt()
                        clickAt(a, PTRFLAGS_RBUTTON)
                    }
                }
                twoFingerTap = false
            }
        }
        true
    }

    init {
        // Step 45 (An): hide the Android system cursor over the remote
        // screen. With a Bluetooth mouse connected, Android draws its own
        // arrow on top of the PC cursor (double cursor). The system
        // pointer only appears when a pointing device is present, so
        // TYPE_NULL changes nothing for touch use — and the keyboard area
        // keeps its arrow, since no PC cursor is drawn there.
        surface.pointerIcon =
            PointerIcon.getSystemIcon(context, PointerIcon.TYPE_NULL)
        clipboardManager.addPrimaryClipChangedListener(clipboardListener)
        surface.setOnTouchListener { _, event -> onTouch(event) }
        surface.holder.addCallback(this)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(synchronized(lock) { snapshot() })
                "connect" -> {
                    val host = call.argument<String>("host")?.trim().orEmpty()
                    val port = call.argument<Int>("port") ?: 0
                    val user = call.argument<String>("username").orEmpty()
                    val password = call.argument<String>("password").orEmpty()
                    synchronized(lock) {
                        if (disposed || attempt != null) result.error("busy", "Phiên trước chưa kết thúc", null)
                        else if (host.isEmpty() || port !in 1..65535 || user.isBlank() || password.isEmpty())
                            result.error("invalid", "Nhập đủ thông tin kết nối", null)
                        else if (loadError != null) { change("failed", loadError); result.success(null) }
                        else {
                            authAttempted = false
                            resizeFailure = null
                            connectStartedAt = SystemClock.elapsedRealtime()
                            connectPhase = "creating"
                            firstFrameLogged = false
                            Log.d("AceRdp", "connect: creating session")
                            val next = Attempt(host, port, user, password)
                            touched = false
                            attempt = next
                            change("connecting")
                            executor.execute { next.start() }
                            result.success(null)
                        }
                    }
                }
                "key" -> {
                    val vk = call.argument<Int>("vk")
                    val down = call.argument<Boolean>("down")
                    if (vk != null && down != null) keyInput(vk, down)
                    result.success(null)
                }
                "cursor" -> {
                    val x = call.argument<Int>("x"); val y = call.argument<Int>("y")
                    val flags = call.argument<Int>("flags")
                    synchronized(lock) {
                        val a = inputAttempt()
                        if (a != null && x != null && y != null && flags != null) cursorInput(a, x, y, flags)
                    }
                    result.success(null)
                }
                "click" -> {
                    val button = call.argument<String>("button")
                    synchronized(lock) {
                        inputAttempt()?.let { a ->
                            if (button == "left" || button == "right")
                                clickAt(a, if (button == "left") PTRFLAGS_LBUTTON else PTRFLAGS_RBUTTON)
                        }
                    }
                    result.success(null)
                }
                "mode" -> {
                    val trackpad = call.argument<Boolean>("trackpad") ?: false
                    val sensitivity =
                        (call.argument<Number>("sensitivity")?.toFloat() ?: 1.5f)
                            .coerceIn(0.5f, 3.0f)
                    synchronized(lock) {
                        if (trackpadMode != trackpad) {
                            trackpadMode = trackpad
                            resetTouch()
                            trackpadCursorX = lastX.toFloat()
                            trackpadCursorY = lastY.toFloat()
                            Log.d("AceRdp", "trackpad mode=" +
                                if (trackpad) "relative" else "absolute")
                        }
                        if (trackpadSensitivity != sensitivity) {
                            trackpadSensitivity = sensitivity
                            Log.d("AceRdp", "trackpad sensitivity=$sensitivity")
                        }
                    }
                    result.success(null)
                }
                "moveRelative" -> {
                    val dx = (call.argument<Number>("dx"))?.toFloat()
                    val dy = (call.argument<Number>("dy"))?.toFloat()
                    if (dx != null && dy != null) {
                        synchronized(lock) {
                            inputAttempt()?.let { a -> moveCursorRelative(a, dx, dy) }
                        }
                    }
                    result.success(null)
                }
                "scroll" -> {
                    val down = call.argument<Boolean>("down") ?: false
                    synchronized(lock) {
                        inputAttempt()?.let { a ->
                            val amount = if (down) -WHEEL_DELTA else WHEEL_DELTA
                            cursorInput(a, lastX, lastY, PTRFLAGS_WHEEL or
                                (if (down) PTRFLAGS_WHEEL_NEGATIVE else 0) or (amount and 0xFF))
                        }
                    }
                    result.success(null)
                }
                // Step 34: physical-mouse input from the Dart mouse layer
                // (absolute position in surface physical pixels; the
                // framebuffer conversion lives here, next to onTouch).
                "mouseMove" -> {
                    val x = (call.argument<Number>("x"))?.toFloat()
                    val y = (call.argument<Number>("y"))?.toFloat()
                    if (x != null && y != null) {
                        synchronized(lock) {
                            val a = inputAttempt()
                            val fb = if (a != null) surfaceToFramebuffer(x, y) else null
                            if (a != null && fb != null) {
                                lastX = fb.first; lastY = fb.second; touched = true
                                cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
                            }
                        }
                    }
                    result.success(null)
                }
                "mouseButton" -> {
                    val x = (call.argument<Number>("x"))?.toFloat()
                    val y = (call.argument<Number>("y"))?.toFloat()
                    val button = call.argument<String>("button")
                    val down = call.argument<Boolean>("down") ?: false
                    if (x != null && y != null && button != null) {
                        synchronized(lock) {
                            val a = inputAttempt()
                            val fb = if (a != null) surfaceToFramebuffer(x, y) else null
                            if (a != null && fb != null) {
                                lastX = fb.first; lastY = fb.second; touched = true
                                val flag = when (button) {
                                    "right" -> PTRFLAGS_RBUTTON
                                    "middle" -> PTRFLAGS_MBUTTON
                                    else -> PTRFLAGS_LBUTTON
                                }
                                // A press is MOVE-then-DOWN (like clickAt);
                                // a release is the bare button flag.
                                if (down) cursorInput(a, lastX, lastY, PTRFLAGS_MOVE)
                                cursorInput(a, lastX, lastY, if (down) flag or PTRFLAGS_DOWN else flag)
                            }
                        }
                    }
                    result.success(null)
                }
                "disconnect" -> { stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    private fun snapshot() = mapOf("connected" to (state == "connected"), "h264" to h264,
        "loadError" to loadError, "widthPx" to widthPx, "heightPx" to heightPx,
        "state" to state, "error" to error, "authAttempted" to authAttempted,
        "resizeFailure" to resizeFailure, "phase" to connectPhase)
    // Shared state and framebuffer copies use lock; Canvas access runs outside it.
    private fun change(value: String, reason: String? = null) {
        state = value; error = reason
        val event = snapshot()
        main.post { synchronized(lock) { if (!disposed) channel.invokeMethod("state", event) } }
    }
    private val renderTask = Runnable { render() }
    private fun draw() {
        main.removeCallbacks(renderTask)
        main.post(renderTask)
    }
    private fun render() {
        val frame = synchronized(lock) {
            if (disposed || !surfaceReady) return
            bitmap?.copy(bitmap!!.config ?: Bitmap.Config.ARGB_8888, false)
        }
        // Cursor position/shape snapshot (under lock). The pointer bitmap
        // reference is only replaced, never recycled, so using it outside
        // the lock is safe.
        var cursorX = 0; var cursorY = 0; var pointer: Bitmap? = null
        var hotX = 0; var hotY = 0
        synchronized(lock) {
            cursorX = lastX; cursorY = lastY
            pointer = pointerBitmap; hotX = pointerHotX; hotY = pointerHotY
        }
        if (!surface.holder.surface.isValid) { frame?.recycle(); return }
        try {
            val canvas = surface.holder.lockCanvas() ?: return
            try {
                canvas.drawColor(Color.BLACK)
                frame?.let {
                    val scale = minOf(canvas.width.toFloat() / it.width, canvas.height.toFloat() / it.height)
                    val w = it.width * scale; val h = it.height * scale
                    val left = (canvas.width - w) / 2; val top = (canvas.height - h) / 2
                    canvas.drawBitmap(it, null, RectF(left, top, left + w, top + h), null)
                    // Remote cursor overlay: the pointer shape is not part of
                    // the framebuffer (FreeRDP sends it via OnPointerSet),
                    // so draw it here at the last known cursor position.
                    // Without a shape (default pointer / none yet), draw a
                    // small fallback arrow so the cursor is always visible.
                    val cx = left + cursorX * scale
                    val cy = top + cursorY * scale
                    if (pointer != null) {
                        val pw = pointer.width * scale; val ph = pointer.height * scale
                        canvas.drawBitmap(pointer, null,
                            RectF(cx - hotX * scale, cy - hotY * scale,
                                cx - hotX * scale + pw, cy - hotY * scale + ph), null)
                    } else {
                        drawDefaultCursor(canvas, cx, cy)
                    }
                }
            } finally { surface.holder.unlockCanvasAndPost(canvas) }
        } catch (_: IllegalArgumentException) { /* Surface may be removed by Android. */ }
          catch (_: IllegalStateException) { /* Wait for surfaceCreated. */ }
        finally { frame?.recycle() }
    }

    // Default remote cursor: a small white arrow with a black outline, drawn
    // when FreeRDP has not sent a pointer shape (default pointer / none yet).
    // Fixed surface size so it stays visible at any framebuffer resolution.
    private val cursorArrowFill = Paint().apply {
        color = Color.WHITE; style = Paint.Style.FILL; isAntiAlias = true
    }
    private val cursorArrowOutline = Paint().apply {
        color = Color.BLACK; style = Paint.Style.STROKE; strokeWidth = 2f
        strokeJoin = Paint.Join.ROUND; isAntiAlias = true
    }
    private fun drawDefaultCursor(canvas: Canvas, x: Float, y: Float) {
        val s = 26f
        val arrow = Path().apply {
            moveTo(x, y)
            lineTo(x, y + s)
            lineTo(x + s * 0.28f, y + s * 0.72f)
            lineTo(x + s * 0.42f, y + s * 1.05f)
            lineTo(x + s * 0.55f, y + s)
            lineTo(x + s * 0.4f, y + s * 0.68f)
            lineTo(x + s * 0.65f, y + s * 0.68f)
            close()
        }
        canvas.drawPath(arrow, cursorArrowOutline)
        canvas.drawPath(arrow, cursorArrowFill)
    }
    override fun surfaceCreated(holder: SurfaceHolder) = synchronized(lock) { surfaceReady = true; draw() }
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = synchronized(lock) {
        widthPx = width; heightPx = height
        scheduleResize(); draw()
    }
    private fun scheduleResize() {
        resizeGeneration++
        main.removeCallbacks(resizeTask)
        if (!disposed && surfaceReady) main.postDelayed(resizeTask, 250)
    }
    override fun surfaceDestroyed(holder: SurfaceHolder) = synchronized(lock) {
        resetTouch(); surfaceReady = false; widthPx = 0; heightPx = 0
        resizeGeneration++; main.removeCallbacks(resizeTask)
    }
    override fun getView(): View = surface
    private fun stop() = synchronized(lock) {
        resetTouch()
        attempt?.let { a ->
            resizeGeneration++; main.removeCallbacks(resizeTask)
            a.stopping = true; a.clearCredentials(); a.session?.setUIEventListener(null)
            bitmap = null; pointerBitmap = null; draw()
            // Serialize with configuration/start; never free a still-connecting worker.
            executor.execute { synchronized(lock) {
                if (attempt === a && !a.terminal && a.handle != 0L) {
                    if (a.connected) LibFreeRDP.disconnect(a.handle) else LibFreeRDP.cancelConnection(a.handle)
                }
            } }
        }
        change(if (attempt == null) "disconnected" else "disconnecting")
    }
    override fun dispose() {
        synchronized(lock) { if (disposed) return; disposed = true; surfaceReady = false }
        channel.setMethodCallHandler(null)
        surface.setOnTouchListener(null)
        clipboardManager.removePrimaryClipChangedListener(clipboardListener)
        main.removeCallbacks(longPress)
        surface.holder.removeCallback(this)
        stop()
        synchronized(lock) { if (attempt == null) executor.shutdown() }
    }

    private inner class Attempt(val host: String, val port: Int, var username: String?, var password: String?) :
        LibFreeRDP.EventListener, LibFreeRDP.UIEventListener {
        var handle = 0L
        var session: SessionState? = null
        var bookmark: BookmarkBase? = null
        var stopping = false
        var connected = false
        var terminal = false
        private var connectedAt = 0L
        private var requestedWidth = 1024
        private var requestedHeight = 768
        // Called with lock held; native calls remain serialized with start/teardown.
        fun resize(generation: Int, retry: Int) {
            if (!valid() || !connected || !surfaceReady || generation != resizeGeneration ||
                widthPx !in 1..65536 || heightPx !in 1..65536 ||
                (widthPx == requestedWidth && heightPx == requestedHeight)) return
            val remaining = 2000 - (SystemClock.uptimeMillis() - connectedAt)
            if (remaining > 0) {
                main.postDelayed({ synchronized(lock) { resize(generation, retry) } }, remaining)
                return
            }
            val w = widthPx; val h = heightPx
            executor.execute { synchronized(lock) {
                if (!valid() || !connected || !surfaceReady || generation != resizeGeneration) return@synchronized
                val sent = try { LibFreeRDP.sendMonitorLayout(handle, w, h) }
                    catch (_: LinkageError) { false } catch (_: RuntimeException) { false }
                if (sent) {
                    requestedWidth = w; requestedHeight = h
                    // true acknowledges channel submission, not a server graphics resize.
                    main.postDelayed({ synchronized(lock) {
                        if (valid() && surfaceReady && generation == resizeGeneration &&
                            (bitmap?.width != w || bitmap?.height != h)) resizeUnavailable()
                    } }, 3000)
                } else if (retry < 2) {
                    main.postDelayed({ synchronized(lock) { resize(generation, retry + 1) } }, 1000)
                } else {
                    resizeUnavailable()
                }
            } }
        }
        private fun resizeUnavailable() {
            resizeFailure = "DISP không đổi được độ phân giải; tiếp tục dùng kích thước hiện tại."
            Log.w("AceRdp", resizeFailure.orEmpty())
            change(state, error)
        }
        private fun valid() = !disposed && !stopping && !terminal && attempt === this && handle != 0L
        fun clearCredentials() { password = null; username = null; bookmark?.setPassword("") }
        fun start() = synchronized(lock) {
            if (disposed || stopping) { finish("disconnected"); return@synchronized }
            try {
                RdpEvents.install(context)
                requestedWidth = if (surfaceReady && widthPx in 1..65536) widthPx else 1024
                requestedHeight = if (surfaceReady && heightPx in 1..65536) heightPx else 768
                val b = BookmarkBase().apply {
                    setType(BookmarkBase.TYPE_MANUAL); setHostname(host); setPort(port); setUsername(username.orEmpty())
                    setDomain(""); setPassword(password.orEmpty())
                    getScreenSettings().setResolution("custom", requestedWidth, requestedHeight)
                    getScreenSettings().setColors(32); getAdvancedSettings().setSecurity(3)
                }
                bookmark = b
                val s = GlobalApp.createSession(b, context.applicationContext)
                Log.d("AceRdp", "connect: session created +" +
                    (SystemClock.elapsedRealtime() - connectStartedAt) + "ms")
                session = s; handle = s.getInstance()
                if (handle == 0L) { finish("failed", "Không tạo được phiên FreeRDP"); return@synchronized }
                RdpEvents.sessions[handle] = this
                s.setUIEventListener(this)
                if (!LibFreeRDP.setConnectionInfo(context.applicationContext, handle, b)) {
                    finish("failed", "FreeRDP từ chối cấu hình"); return@synchronized
                }
                Log.d("AceRdp", "connect: connection info set +" +
                    (SystemClock.elapsedRealtime() - connectStartedAt) + "ms")
                b.setPassword("") // Native settings now own their in-memory copy.
                if (!LibFreeRDP.connect(handle)) finish("failed", "Không khởi động được kết nối")
                Log.d("AceRdp", "connect: connect() called +" +
                    (SystemClock.elapsedRealtime() - connectStartedAt) + "ms")
            } catch (_: LinkageError) { finish("failed", "Không tải được FreeRDP") }
              catch (_: RuntimeException) { finish("failed", "Không khởi tạo được kết nối") }
        }
        private fun finish(value: String, reason: String? = null) {
            if (terminal) return
            terminal = true; clearCredentials(); session?.setUIEventListener(null)
            // Never free inside the native callback. freeInstance may wait for wrapper state.
            executor.execute {
                if (session != null) GlobalApp.freeSession(handle)
                RdpEvents.sessions.remove(handle, this)
                synchronized(lock) {
                    session = null; bookmark = null
                    if (attempt === this) {
                        attempt = null; bitmap = null; pointerBitmap = null; draw()
                        if (!disposed) change(if (stopping) "disconnected" else value,
                            if (stopping) null else reason)
                    }
                    if (disposed) executor.shutdown()
                }
            }
        }
        override fun OnPreConnect(instance: Long) = synchronized(lock) {
            if (valid() && instance == handle) {
                connectPhase = "connecting"
                Log.d("AceRdp", "connect: pre-connect +" +
                    (SystemClock.elapsedRealtime() - connectStartedAt) + "ms")
                change("connecting")
            }
        }
        override fun OnConnectionSuccess(instance: Long) = synchronized(lock) {
            if (instance != handle || terminal || attempt !== this) return@synchronized
            connected = true; connectedAt = SystemClock.uptimeMillis(); clearCredentials()
            connectPhase = ""
            Log.d("AceRdp", "connect: success +" +
                (SystemClock.elapsedRealtime() - connectStartedAt) + "ms")
            if (disposed || stopping) executor.execute { synchronized(lock) {
                if (!terminal && attempt === this) LibFreeRDP.disconnect(instance)
            } }
            else { change("connected"); scheduleResize(); pushLocalClipboard() }
        }
        override fun OnConnectionFailure(instance: Long) = synchronized(lock) {
            if (instance == handle && attempt === this) finish("failed", if (authAttempted)
                "Kết nối thất bại; đã đi qua callback xác thực. Chưa xác định nguyên nhân."
                else "Kết nối thất bại; chưa đi qua callback xác thực. Chưa xác định nguyên nhân.")
        }
        override fun OnDisconnected(instance: Long) = synchronized(lock) { if (instance == handle && attempt === this) finish("disconnected") }
        override fun OnDisconnecting(instance: Long) = synchronized(lock) { if (valid() && instance == handle) change("disconnecting") }
        override fun OnReconnecting() = synchronized(lock) { if (valid()) change("connecting") }
        override fun OnAuthenticate(username: StringBuilder, domain: StringBuilder, password: StringBuilder): Boolean = synchronized(lock) {
            if (!valid()) return@synchronized false
            authAttempted = true
            connectPhase = "auth"
            Log.d("AceRdp", "connect: NLA auth +" +
                (SystemClock.elapsedRealtime() - connectStartedAt) + "ms")
            change("connecting")
            val u = this.username ?: return@synchronized false
            val p = this.password ?: return@synchronized false
            username.setLength(0); username.append(u); domain.setLength(0)
            password.setLength(0); password.append(p)
            clearCredentials()
            true
        }
        override fun OnGatewayAuthenticate(username: StringBuilder, domain: StringBuilder, password: StringBuilder) = false
        override fun OnVerifiyCertificateEx(host: String, port: Long, commonName: String, subject: String, issuer: String, fingerprint: String, flags: Long): Int = synchronized(lock) { if (valid()) 2 else 0 }
        override fun OnVerifyChangedCertificateEx(host: String, port: Long, commonName: String, subject: String, issuer: String, fingerprint: String, oldSubject: String, oldIssuer: String, oldFingerprint: String, flags: Long): Int = synchronized(lock) { if (valid()) 2 else 0 }
        override fun OnExperimentalFeature(feature: Int) = false
        override fun OnSettingsChanged(width: Int, height: Int, bpp: Int) = synchronized(lock) {
            if (valid() && width > 0 && height > 0) {
                resetTouch()
                bitmapWidth = width; bitmapHeight = height
                if (!touched || lastX >= width || lastY >= height) {
                    lastX = width / 2; lastY = height / 2
                }
                if (bitmap == null && !firstFrameLogged) {
                    firstFrameLogged = true
                    Log.d("AceRdp", "connect: first frame +" +
                        (SystemClock.elapsedRealtime() - connectStartedAt) + "ms")
                }
                bitmap = Bitmap.createBitmap(width, height, if (bpp == 16) Bitmap.Config.RGB_565 else Bitmap.Config.ARGB_8888)
                session?.setSurface(BitmapDrawable(context.resources, bitmap))
                draw()
            }
        }
        override fun OnGraphicsResize(width: Int, height: Int, bpp: Int) = OnSettingsChanged(width, height, bpp)
        override fun OnGraphicsUpdate(x: Int, y: Int, width: Int, height: Int) = synchronized(lock) {
            if (valid()) bitmap?.let { if (LibFreeRDP.updateGraphics(handle, it, x, y, width, height)) draw() }
            Unit
        }
        override fun OnRemoteClipboardChanged(data: String) {
            // Text only (images stay ignored). Post to main: clipboard
            // writes belong on the UI thread, and the echo guard must be
            // set before the write so our own listener skips the bounce.
            main.post {
                synchronized(lock) {
                    if (disposed) return@synchronized
                    lastRemoteText = data
                    clipboardManager.setPrimaryClip(
                        ClipData.newPlainText("rdp-clipboard", data))
                    Log.d("AceRdp", "clipboard: PC -> phone (${data.length} chars)")
                }
            }
        }
        override fun OnRemoteClipboardImageChanged(data: ByteArray) {}
        override fun OnPointerSet(pixels: IntArray, width: Int, height: Int, hotX: Int, hotY: Int) = synchronized(lock) {
            // The remote cursor shape: stored and drawn by render() as an
            // overlay at the last known cursor position. Without it the
            // cursor would be invisible (it is not part of the framebuffer).
            if (valid() && width > 0 && height > 0 && pixels.size >= width * height) {
                pointerBitmap = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
                pointerHotX = hotX; pointerHotY = hotY
                draw()
            }
        }
        override fun OnPointerSetNull() = synchronized(lock) {
            pointerBitmap = null; draw()
        }
        override fun OnPointerSetDefault() = synchronized(lock) {
            // No custom shape: render() draws the fallback arrow instead.
            pointerBitmap = null; draw()
        }
        override fun OnRailWindowUpdate(windowId: Long, width: Int, height: Int, pixels: IntArray) {}
        override fun OnRailWindowMove(windowId: Long, x: Int, y: Int, w: Int, h: Int) {}
        override fun OnRailWindowHide(windowId: Long) {}
        override fun OnRailWindowDestroy(windowId: Long) {}
        override fun OnRailSessionEnd() {}
        override fun OnRailMonitoredDesktop(windowIds: LongArray, activeWindowId: Long) {}
    }
}
