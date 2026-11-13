import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class RdpController extends ValueNotifier<Map<String, dynamic>> {
  RdpController() : super({'state': 'idle'});
  MethodChannel? _channel;
  Future<void> attach(int id) async {
    final channel = MethodChannel('vn.aceremote.app/rdp/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'state' && _channel == channel) {
        value = Map<String, dynamic>.from(call.arguments as Map);
      }
    });
    final initial = await channel.invokeMapMethod<String, dynamic>('status');
    if (_channel == channel && initial != null) value = initial;
  }

  Future<void> connect(String host, int port, String username, String password) async {
    final channel = _channel;
    if (channel == null) throw PlatformException(code: 'unavailable');
    await channel.invokeMethod<void>('connect', {
      'host': host, 'port': port, 'username': username, 'password': password,
    });
  }

  bool get isConnected => value['state'] == 'connected';
  Future<void> sendKey(int vk, bool down) async {
    await _channel?.invokeMethod<void>('key', {'vk': vk, 'down': down});
  }

  Future<void> sendCursor(int x, int y, int flags) async {
    await _channel
        ?.invokeMethod<void>('cursor', {'x': x, 'y': y, 'flags': flags});
  }

  Future<void> clickAtLastPosition(String button) async {
    await _channel?.invokeMethod<void>('click', {'button': button});
  }

  Future<void> disconnect() async { await _channel?.invokeMethod<void>('disconnect'); }
  Future<Map<String, dynamic>?> status() async =>
      _channel?.invokeMapMethod<String, dynamic>('status');
  void detach() { _channel?.setMethodCallHandler(null); _channel = null; }
  @override
  void dispose() { detach(); super.dispose(); }
}

class RdpSurface extends StatefulWidget {
  const RdpSurface({super.key, this.controller});
  final RdpController? controller;
  @override
  State<RdpSurface> createState() => _RdpSurfaceState();
}

class _RdpSurfaceState extends State<RdpSurface> {
  late final controller = widget.controller ?? RdpController();
  @override
  void dispose() {
    controller.detach();
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Center(child: Text('RDP chỉ hỗ trợ Android'));
    }
    return AndroidView(
      viewType: 'vn.aceremote.app/rdp',
      onPlatformViewCreated: (id) async {
        try { await controller.attach(id); }
        on PlatformException {
          if (mounted) controller.value = {'state': 'failed', 'error': 'Không mở được RDP'};
        }
      },
    );
  }
}

/// Owns credentials only while the RDP login form is mounted.
class RdpConnectionPane extends StatefulWidget {
  const RdpConnectionPane({super.key, this.controller});
  final RdpController? controller;
  @override
  State<RdpConnectionPane> createState() => _RdpConnectionPaneState();
}

class _RdpConnectionPaneState extends State<RdpConnectionPane> {
  late final controller = widget.controller ?? RdpController();
  final host = TextEditingController(text: '100.101.127.41');
  final port = TextEditingController(text: '3389');
  final username = TextEditingController();
  final password = TextEditingController();
  bool submitting = false;
  String? localError;
  @override
  void dispose() {
    password.clear();
    for (final field in [host, port, username, password]) { field.dispose(); }
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }
  Future<void> connect() async {
    final number = int.tryParse(port.text);
    if (host.text.trim().isEmpty || number == null || number < 1 || number > 65535 || username.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => localError = 'Nhập đủ thông tin; port từ 1 đến 65535');
      return;
    }
    setState(() { submitting = true; localError = null; });
    try {
      await controller.connect(host.text.trim(), number, username.text.trim(), password.text);
    } on PlatformException {
      if (mounted) setState(() => localError = 'Không gửi được yêu cầu kết nối. Hãy thử lại.');
    } finally {
      if (mounted) {
        password.clear();
        setState(() => submitting = false);
      }
    }
  }
  Future<void> disconnect() async {
    password.clear();
    try { await controller.disconnect(); }
    on PlatformException {
      if (mounted) setState(() => localError = 'Không gửi được yêu cầu ngắt kết nối.');
    }
  }
  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: RdpSurface(controller: controller)),
    Positioned.fill(child: ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: controller,
      builder: (context, status, _) {
        final state = status['state'];
        if (state == 'connected') {
          return Align(alignment: Alignment.topRight, child: SafeArea(bottom: false,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Chip(label: Text('Đã kết nối')),
              FilledButton(onPressed: disconnect, child: const Text('Ngắt kết nối')),
            ])));
        }
        final busy = submitting || state == 'connecting' || state == 'disconnecting';
        return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(12),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400),
            child: Card(child: Padding(padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (busy) ...[
                  Text(state == 'disconnecting' ? 'Đang ngắt kết nối…' : 'Đang kết nối…'),
                  TextButton(onPressed: state == 'disconnecting' ? null : disconnect, child: const Text('Ngắt')),
                ] else ...[
                  if (state == 'failed') ...[
                    Text(status['error'] as String? ?? 'Kết nối thất bại'),
                    Text(status['authAttempted'] == true
                      ? 'Đã đi qua callback xác thực; chưa xác định nguyên nhân.'
                      : 'Chưa đi qua callback xác thực; chưa xác định nguyên nhân.'),
                  ],
                  if (localError != null) Text(localError!),
                  TextField(key: const ValueKey('rdp-host'), controller: host, decoration: const InputDecoration(labelText: 'Host')),
                  TextField(key: const ValueKey('rdp-port'), controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port')),
                  TextField(key: const ValueKey('rdp-username'), controller: username, autocorrect: false, decoration: const InputDecoration(labelText: 'Username')),
                  TextField(key: const ValueKey('rdp-password'), controller: password, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Password')),
                  FilledButton(onPressed: connect, child: Text(state == 'failed' ? 'Kết nối lại' : 'Kết nối')),
                ],
              ]))))));
      },
    )),
  ]);
}
