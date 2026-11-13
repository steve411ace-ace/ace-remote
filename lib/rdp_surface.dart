import 'dart:async';
import 'rdp_credentials.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class RdpController extends ValueNotifier<Map<String, dynamic>> {
  RdpController() : super({'state': 'idle'});
  MethodChannel? _channel;

  /// Relative-touch (trackpad) mode. Single source of truth observed by the
  /// header toggle and the bottom half (keyboard vs trackpad). Sent to native
  /// via the 'mode' channel call; the native side owns the cursor position.
  final trackpadMode = ValueNotifier<bool>(false);

  /// Bottom-half (keyboard / trackpad) visibility. False = the remote screen
  /// fills the whole RemotePage. Observed by RemotePage's RDP layout.
  final keyboardVisible = ValueNotifier<bool>(true);

  /// Switch touch mode. Sends the mode to native (fire-and-forget if the
  /// view is not attached yet; attach() re-sends the current mode).
  Future<void> setTrackpadMode(bool value) async {
    if (trackpadMode.value == value) return;
    trackpadMode.value = value;
    await _sendMode();
  }

  void setKeyboardVisible(bool value) {
    keyboardVisible.value = value;
  }

  Future<void> _sendMode() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>(
          'mode', {'trackpad': trackpadMode.value});
    } on PlatformException {
      // Native side not ready; the mode is kept in Dart and re-sent on attach.
    }
  }

  /// Move the cursor by a relative delta (surface physical pixels). The native
  /// side converts to framebuffer pixels with the trackpad sensitivity.
  Future<void> moveRelative(Offset deltaPhysicalPx) async {
    await _channel?.invokeMethod<void>(
        'moveRelative', {'dx': deltaPhysicalPx.dx, 'dy': deltaPhysicalPx.dy});
  }

  /// Send one wheel notch at the current cursor position.
  Future<void> scrollWheel(bool down) async {
    await _channel?.invokeMethod<void>('scroll', {'down': down});
  }

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
    // Re-send the current touch mode in case it was toggled before attach.
    if (_channel == channel) await _sendMode();
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
  void dispose() {
    detach();
    trackpadMode.dispose();
    keyboardVisible.dispose();
    super.dispose();
  }
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

/// Restores credentials from secure storage and saves only after native success.
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
  String? pendingPassword;
  String? pendingUsername;
  bool passwordEdited = false;
  bool usernameEdited = false;
  Future<void> storageQueue = Future<void>.value();
  // Connected-header auto-hide: the header hides a few seconds after connect
  // so it stops covering the remote screen; a small button brings it back.
  bool headerVisible = true;
  Timer? headerHideTimer;

  @override
  void initState() {
    super.initState();
    controller.addListener(connectionChanged);
    unawaited(restoreCredentials());
  }

  Future<void> restoreCredentials() async {
    try {
      final savedUser =
          await storage.read(key: rdpUsernameKey, aOptions: rdpStorageOptions);
      final savedSecret =
          await storage.read(key: rdpPasswordKey, aOptions: rdpStorageOptions);
      if (!mounted || submitting) return;
      if (!usernameEdited) username.text = savedUser ?? '';
      if (!passwordEdited) password.text = savedSecret ?? '';
    } on PlatformException {
      if (mounted) {
        setState(() => localError = 'Không đọc được thông tin đăng nhập đã lưu.');
      }
    }
  }

  void connectionChanged() {
    if (controller.isConnected) {
      showHeaderTemporarily();
      if (pendingPassword != null) {
        final secret = pendingPassword!;
        pendingPassword = null;
        queueStorage(() => storage.write(
            key: rdpPasswordKey, value: secret, aOptions: rdpStorageOptions));
      }
      if (pendingUsername != null) {
        final user = pendingUsername!;
        pendingUsername = null;
        queueStorage(() => storage.write(
            key: rdpUsernameKey, value: user, aOptions: rdpStorageOptions));
      }
    } else if (['failed', 'disconnected', 'disconnecting']
        .contains(controller.value['state'])) {
      headerHideTimer?.cancel();
      headerVisible = true;
      pendingPassword = null;
      pendingUsername = null;
      if (controller.value['state'] == 'failed' ||
          controller.value['state'] == 'disconnected') {
        // Login form is visible again: refill the saved credentials so the
        // user does not have to retype them to reconnect. restoreCredentials()
        // still respects the *Edited flags (set by onChanged) if the user
        // types first.
        passwordEdited = false;
        usernameEdited = false;
        unawaited(restoreCredentials());
      }
    }
  }

  /// Show the connected header and hide it again after 3 seconds.
  void showHeaderTemporarily() {
    headerHideTimer?.cancel();
    if (!headerVisible && mounted) setState(() => headerVisible = true);
    headerHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && controller.isConnected) {
        setState(() => headerVisible = false);
      }
    });
  }

  void toggleTrackpadMode() {
    unawaited(
        controller.setTrackpadMode(!controller.trackpadMode.value));
    showHeaderTemporarily();
  }

  void toggleKeyboardVisible() {
    controller.setKeyboardVisible(!controller.keyboardVisible.value);
    showHeaderTemporarily();
  }

  void queueStorage(Future<void> Function() action) {
    storageQueue = storageQueue.then((_) => action()).catchError((Object error) {
      if (mounted) setState(() => localError = 'Không cập nhật được mật khẩu đã lưu.');
    });
  }

  @override
  void dispose() {
    headerHideTimer?.cancel();
    controller.removeListener(connectionChanged);
    pendingPassword = null;
    pendingUsername = null;
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
    FocusScope.of(context).unfocus();
    passwordEdited = true;
    usernameEdited = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      pendingPassword = password.text;
      pendingUsername = username.text.trim();
      await controller.connect(host.text.trim(), number, username.text.trim(), password.text);
    } on PlatformException {
      pendingPassword = null;
      pendingUsername = null;
      if (mounted) setState(() => localError = 'Không gửi được yêu cầu kết nối. Hãy thử lại.');
    } finally {
      if (mounted) {
        password.clear();
        setState(() => submitting = false);
      }
    }
  }
  Future<void> disconnect() async {
    pendingPassword = null;
    pendingUsername = null;
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
          // The header auto-hides a few seconds after connect so it stops
          // covering the remote screen; a small button brings it back.
          // The mode / keyboard toggles live here so they stay reachable
          // even when the keyboard is hidden (never inside the keyboard area).
          return Align(alignment: Alignment.topRight, child: SafeArea(bottom: false,
            child: ValueListenableBuilder<bool>(
              valueListenable: controller.trackpadMode,
              builder: (context, isTrackpad, _) => ValueListenableBuilder<bool>(
                valueListenable: controller.keyboardVisible,
                builder: (context, kbVisible, _) => headerVisible
                    ? Wrap(alignment: WrapAlignment.end, spacing: 6, children: [
                        const Chip(label: Text('Đã kết nối')),
                        FilledButton.tonal(
                            onPressed: toggleTrackpadMode,
                            child: Text(isTrackpad ? 'Chạm' : 'Trackpad')),
                        FilledButton.tonal(
                            onPressed: toggleKeyboardVisible,
                            child: Text(kbVisible ? 'Ẩn bàn phím' : 'Hiện bàn phím')),
                        FilledButton(
                            onPressed: disconnect,
                            child: const Text('Ngắt kết nối')),
                      ])
                    : IconButton(
                        tooltip: 'Hiện điều khiển',
                        onPressed: showHeaderTemporarily,
                        icon: const Icon(Icons.expand_more),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                            foregroundColor: Colors.white),
                      ),
              ),
            )));
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
                  TextField(key: const ValueKey('rdp-username'), controller: username, onChanged: (_) => usernameEdited = true, autocorrect: false, decoration: const InputDecoration(labelText: 'Username')),
                  TextField(key: const ValueKey('rdp-password'), controller: password, onChanged: (_) => passwordEdited = true, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Password')),
                  FilledButton(onPressed: connect, child: Text(state == 'failed' ? 'Kết nối lại' : 'Kết nối')),
                ],
              ]))))));
      },
    )),
  ]);
}
