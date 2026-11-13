package vn.aceremote.app

import android.content.Context
import android.graphics.Color
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.freerdp.freerdpcore.services.LibFreeRDP
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** App-local plugin; deliberately does not allocate or connect a native session. */
class RdpPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding.platformViewRegistry.registerViewFactory(
            "vn.aceremote.app/rdp", RdpFactory(binding)
        )
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}

private class RdpFactory(private val binding: FlutterPlugin.FlutterPluginBinding) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        RdpWaitingView(context, viewId, binding)
}

private class RdpWaitingView(
    context: Context, id: Int, binding: FlutterPlugin.FlutterPluginBinding
) : PlatformView {
    private val root = FrameLayout(context)
    private val surface = SurfaceView(context)
    private val channel = MethodChannel(binding.binaryMessenger, "vn.aceremote.app/rdp/$id")
    private var loadError: String? = null
    private val h264 = try {
        LibFreeRDP.hasH264Support()
    } catch (error: LinkageError) {
        loadError = error.toString()
        false
    } catch (error: RuntimeException) {
        loadError = error.toString()
        false
    }

    init {
        root.setBackgroundColor(Color.BLACK)
        root.addView(surface, FrameLayout.LayoutParams(-1, -1))
        root.addView(TextView(context).apply {
            setTextColor(Color.WHITE)
            gravity = android.view.Gravity.CENTER
            text = if (loadError == null) "FreeRDP — chưa kết nối"
                   else "Không tải được FreeRDP"
        }, FrameLayout.LayoutParams(-1, -1))
        channel.setMethodCallHandler { call, result ->
            if (call.method == "status") {
                result.success(mapOf(
                    "connected" to false, "h264" to h264, "loadError" to loadError,
                    "widthPx" to surface.width, "heightPx" to surface.height
                ))
            } else result.notImplemented()
        }
    }
    override fun getView(): View = root
    override fun dispose() { channel.setMethodCallHandler(null) }
}
