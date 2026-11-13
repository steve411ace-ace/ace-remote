import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Waiting surface only. No connection, credentials or JNI input yet.
class RdpSurface extends StatelessWidget {
  const RdpSurface({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Center(child: Text('RDP chỉ hỗ trợ Android'));
    }
    return AndroidView(
      viewType: 'vn.aceremote.app/rdp',
      onPlatformViewCreated: (id) async {
        // Android reports actual surface pixels, including density and resize.
        // A later connection must negotiate these dimensions, not a fixed desktop.
        await MethodChannel('vn.aceremote.app/rdp/$id')
            .invokeMapMethod<String, dynamic>('status');
      },
    );
  }
}
