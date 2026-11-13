package vn.aceremote.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.RectF
import android.graphics.drawable.BitmapDrawable
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
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
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding.platformViewRegistry.registerViewFactory("vn.aceremote.app/rdp", RdpFactory(binding))
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
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
        scrollMode = false; scrollAccum = 0f
        lastMovePending = null
    }
    private fun onTouch(event: MotionEvent): Boolean = synchronized(lock) {
        val a = inputAttempt()
        if (a == null || bitmap == null || !surfaceReady) {
            resetTouch(false)
            return@synchronized false
        }
        val scale = minOf(widthPx.toFloat() / bitmapWidth, heightPx.toFloat() / bitmapHeight)
        if (scale <= 0f) return@synchronized true
        val x = (event.x - (widthPx - bitmapWidth * scale) / 2) / scale
        val y = (event.y - (heightPx - bitmapHeight * scale) / 2) / scale
        if (x < 0 || y < 0 || x >= bitmapWidth || y >= bitmapHeight) {
            // Letterbox is not a framebuffer point: swallow without sending.
            // Cancel the timer so a long press cannot fire while outside.
            main.removeCallbacks(longPress)
            return@synchronized true
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
                    leftHeld = false; scrollMode = true
                    scrollY = (event.getY(0) + event.getY(1)) / 2; scrollAccum = 0f
                }
            }
            MotionEvent.ACTION_MOVE -> if (touchOwner === a) {
                if (scrollMode) {
                    if (event.pointerCount >= 2) {
                        val centerY = (event.getY(0) + event.getY(1)) / 2
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
            MotionEvent.ACTION_POINTER_UP -> main.removeCallbacks(longPress)
        }
        true
    }

    init {
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
                "disconnect" -> { stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    private fun snapshot() = mapOf("connected" to (state == "connected"), "h264" to h264,
        "loadError" to loadError, "widthPx" to widthPx, "heightPx" to heightPx,
        "state" to state, "error" to error, "authAttempted" to authAttempted)
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
        if (!surface.holder.surface.isValid) { frame?.recycle(); return }
        try {
            val canvas = surface.holder.lockCanvas() ?: return
            try {
                canvas.drawColor(Color.BLACK)
                frame?.let {
                    val scale = minOf(canvas.width.toFloat() / it.width, canvas.height.toFloat() / it.height)
                    val w = it.width * scale; val h = it.height * scale
                    canvas.drawBitmap(it, null, RectF((canvas.width-w)/2, (canvas.height-h)/2,
                        (canvas.width+w)/2, (canvas.height+h)/2), null)
                }
            } finally { surface.holder.unlockCanvasAndPost(canvas) }
        } catch (_: IllegalArgumentException) { /* Surface may be removed by Android. */ }
          catch (_: IllegalStateException) { /* Wait for surfaceCreated. */ }
        finally { frame?.recycle() }
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
            bitmap = null; draw()
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
        private var requestedWidth = 1024
        private var requestedHeight = 768
        // Called with lock held; native calls remain serialized with start/teardown.
        fun resize(generation: Int, retry: Int) {
            if (!valid() || !connected || !surfaceReady || generation != resizeGeneration ||
                widthPx !in 1..65536 || heightPx !in 1..65536 ||
                (widthPx == requestedWidth && heightPx == requestedHeight)) return
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
                } else if (retry < 9) {
                    main.postDelayed({ synchronized(lock) { resize(generation, retry + 1) } }, 500)
                } else {
                    resizeUnavailable()
                }
            } }
        }
        private fun resizeUnavailable() {
            resizeFailure = "Không đổi được độ phân giải qua DISP. Nhập lại mật khẩu và kết nối lại để dùng kích thước mới."
            stop()
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
                session = s; handle = s.getInstance()
                if (handle == 0L) { finish("failed", "Không tạo được phiên FreeRDP"); return@synchronized }
                RdpEvents.sessions[handle] = this
                s.setUIEventListener(this)
                if (!LibFreeRDP.setConnectionInfo(context.applicationContext, handle, b)) {
                    finish("failed", "FreeRDP từ chối cấu hình"); return@synchronized
                }
                b.setPassword("") // Native settings now own their in-memory copy.
                if (!LibFreeRDP.connect(handle)) finish("failed", "Không khởi động được kết nối")
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
                        attempt = null; bitmap = null; draw()
                        if (!disposed) change(if (resizeFailure != null) "failed" else if (stopping) "disconnected" else value,
                            resizeFailure ?: if (stopping) null else reason)
                    }
                    if (disposed) executor.shutdown()
                }
            }
        }
        override fun OnPreConnect(instance: Long) = synchronized(lock) { if (valid() && instance == handle) change("connecting") }
        override fun OnConnectionSuccess(instance: Long) = synchronized(lock) {
            if (instance != handle || terminal || attempt !== this) return@synchronized
            connected = true; clearCredentials()
            if (disposed || stopping) executor.execute { synchronized(lock) {
                if (!terminal && attempt === this) LibFreeRDP.disconnect(instance)
            } }
            else { change("connected"); scheduleResize() }
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
        override fun OnRemoteClipboardChanged(data: String) {}
        override fun OnRemoteClipboardImageChanged(data: ByteArray) {}
        override fun OnPointerSet(pixels: IntArray, width: Int, height: Int, hotX: Int, hotY: Int) {}
        override fun OnPointerSetNull() {}
        override fun OnPointerSetDefault() {}
        override fun OnRailWindowUpdate(windowId: Long, width: Int, height: Int, pixels: IntArray) {}
        override fun OnRailWindowMove(windowId: Long, x: Int, y: Int, w: Int, h: Int) {}
        override fun OnRailWindowHide(windowId: Long) {}
        override fun OnRailWindowDestroy(windowId: Long) {}
        override fun OnRailSessionEnd() {}
        override fun OnRailMonitoredDesktop(windowIds: LongArray, activeWindowId: Long) {}
    }
}
