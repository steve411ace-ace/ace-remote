import 'dart:async';
import 'rdp_connections.dart';
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

  /// Step 34: physical-mouse absolute move (surface physical pixels).
  /// The native side converts to framebuffer pixels with the same
  /// aspect-fit mapping touch uses; points in the letterbox are ignored.
  Future<void> sendMouseMove(Offset surfacePhysicalPx) async {
    try {
      await _channel?.invokeMethod<void>('mouseMove',
          {'x': surfacePhysicalPx.dx, 'y': surfacePhysicalPx.dy});
    } on PlatformException {
      // View detached mid-flight (e.g. leaving the page); a hover must
      // never surface an error.
    }
  }

  /// Step 34: physical-mouse button press/release at a surface-physical
  /// position. [button] is 'left', 'right' or 'middle'.
  Future<void> sendMouseButton(
      Offset surfacePhysicalPx, String button, bool down) async {
    try {
      await _channel?.invokeMethod<void>('mouseButton', {
        'x': surfacePhysicalPx.dx,
        'y': surfacePhysicalPx.dy,
        'button': button,
        'down': down,
      });
    } on PlatformException {
      // Same as sendMouseMove: never fail the UI for a detached view.
    }
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

/// Step 34: whether a physical mouse is currently connected to the phone.
/// Backed by the native 'vn.aceremote.app/input' channel (Android
/// InputDeviceListener): Dart asks once for the current state and native
/// pushes 'mouseChanged' on plug/unplug. Without the channel (tests, web)
/// it simply stays false.
class MouseConnection {
  static final ValueNotifier<bool> connected = ValueNotifier<bool>(false);
  static MethodChannel? _channel;
  static bool _started = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel = const MethodChannel('vn.aceremote.app/input');
    _channel!.setMethodCallHandler((call) async {
      if (call.method == 'mouseChanged') {
        final args = call.arguments;
        if (args is Map) connected.value = args['connected'] == true;
      }
    });
    try {
      final current = await _channel!.invokeMethod<bool>('isMouseConnected');
      if (current != null) connected.value = current;
    } catch (_) {
      // No native input channel (tests / non-Android): stay disconnected.
      // Catch everything here — MissingPluginException is NOT a
      // PlatformException, so `on PlatformException` would miss it and the
      // uncaught error would fail the caller (seen in remote_test.dart).
    }
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
  const RdpConnectionPane({super.key, this.controller, this.initialConnection});
  final RdpController? controller;
  // Step 23, item 6: the saved connection tapped on Home. Its host/port are
  // prefilled and its stored user/pass are loaded; when both are present the
  // pane connects right away. Null = the legacy path (last-used credentials
  // from step 21).
  final RdpConnection? initialConnection;
  @override
  State<RdpConnectionPane> createState() => _RdpConnectionPaneState();
}

class _RdpConnectionPaneState extends State<RdpConnectionPane>
    with WidgetsBindingObserver {
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
  // Step 26, item 1: ABSOLUTE watchdog deadline for a stuck
  // connecting/disconnecting state. Step 25 re-armed the 30s timer on
  // every phase event — but FreeRDP's auto-reconnect loop (up to 20
  // retries; each retry fires OnReconnecting / OnPreConnect /
  // OnAuthenticate, i.e. a fresh 'connecting' event every few seconds)
  // kept resetting it, so the timer never elapsed and the spinner sat
  // forever ("Đang kết nối..." hoài). Now the deadline is set ONCE,
  // when the busy episode STARTS (_busySince), and phase changes do not
  // move it; _busyWatchdog is a single timer that fires at that
  // deadline. Re-querying the status (_resumeRdp) also re-fires this
  // listener, but _busySince ??= / _busyWatchdog ??= keep the original
  // deadline.
  Timer? _busyWatchdog;
  DateTime? _busySince;
  // Step 26, item 1: true once a session has connected. The resume
  // handler only auto-reconnects a session the user actually had: it
  // never auto-connects a fresh page (never connected) and never
  // reconnects after the user tapped "Ngắt" to cancel.
  bool _resumeReconnectArmed = false;
  // Guards _resumeReconnect() so two resumes (or a resume racing the
  // watchdog) can never start two fresh connects.
  bool _resumeReconnectRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(connectionChanged);
    final connection = widget.initialConnection;
    if (connection != null) {
      host.text = connection.host;
      port.text = connection.port.toString();
      // Step 23 redesign (04:03): trackpad mode and keyboard visibility are
      // per-connection settings from the Edit screen, not buttons on the
      // remote screen any more. Apply them after the first frame: setting
      // keyboardVisible notifies RemotePage's layout listener, which must
      // not happen while the page is still building (initState runs during
      // the parent's build). setTrackpadMode re-sends the mode on attach if
      // the channel is not ready yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(controller.setTrackpadMode(connection.trackpadMode));
        controller.setKeyboardVisible(connection.keyboardVisible);
      });
      unawaited(_loadConnectionCredentials());
    } else {
      unawaited(restoreCredentials());
    }
  }

  /// Step 23, item 6: fills the form from the tapped saved connection and
  /// connects right away when its user/pass are complete. With
  /// [autoConnect] false it only refills the form (used after a failed or
  /// dropped connection, so a failure does not loop back into a reconnect).
  Future<void> _loadConnectionCredentials({bool autoConnect = true}) async {
    final connection = widget.initialConnection;
    if (connection == null) return;
    final store = RdpConnectionStore();
    try {
      final user = await store.usernameFor(connection.id);
      final secret = await store.passwordFor(connection.id);
      if (!mounted || submitting) return;
      if (!usernameEdited) username.text = user;
      if (!passwordEdited) password.text = secret;
      if (autoConnect &&
          username.text.trim().isNotEmpty &&
          password.text.isNotEmpty) {
        unawaited(connect());
      }
    } on PlatformException {
      if (mounted) {
        setState(() => localError = 'Không đọc được thông tin đăng nhập đã lưu.');
      }
    }
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
    // Step 26, item 1: the busy-episode deadline is set ONCE (see the
    // _busySince comment above). A phase change (creating -> auth ->
    // connecting) or a status re-query only re-enters this listener; it
    // must not move the deadline, or the FreeRDP auto-reconnect loop
    // (a fresh 'connecting' event per retry) postpones the watchdog
    // forever — the exact step 25 failure.
    final busyState = controller.value['state'];
    if (busyState == 'connecting' || busyState == 'disconnecting') {
      _busySince ??= DateTime.now();
      _busyWatchdog ??=
          Timer(const Duration(seconds: 30), _onBusyTimeout);
    } else {
      _busyWatchdog?.cancel();
      _busyWatchdog = null;
      _busySince = null;
    }
    if (controller.isConnected) {
      // A live session arms the resume auto-reconnect (step 26, item 1).
      _resumeReconnectArmed = true;
      if (pendingPassword != null) {
        final secret = pendingPassword!;
        pendingPassword = null;
        // Capture now: the queued closures run after this block, when
        // pendingUsername is already null.
        final user = pendingUsername ?? username.text.trim();
        queueStorage(() => storage.write(
            key: rdpPasswordKey, value: secret, aOptions: rdpStorageOptions));
        // Step 23, item 6: the connection in use keeps its own copy of the
        // credentials, so a user/pass edited in this form is saved back to
        // it (and the next tap on its card connects with the new values).
        final connection = widget.initialConnection;
        if (connection != null) {
          queueStorage(() => RdpConnectionStore()
              .saveCredentials(connection.id, username: user, password: secret));
        }
      }
      if (pendingUsername != null) {
        final user = pendingUsername!;
        pendingUsername = null;
        queueStorage(() => storage.write(
            key: rdpUsernameKey, value: user, aOptions: rdpStorageOptions));
      }
    } else if (['failed', 'disconnected', 'disconnecting']
        .contains(controller.value['state'])) {
      pendingPassword = null;
      pendingUsername = null;
      if (controller.value['state'] == 'failed' ||
          controller.value['state'] == 'disconnected') {
        // Login form is visible again: refill the saved credentials so the
        // user does not have to retype them to reconnect. restoreCredentials()
        // still respects the *Edited flags (set by onChanged) if the user
        // types first. With a saved connection the refill comes from that
        // connection (and never auto-connects, so a failure does not loop).
        passwordEdited = false;
        usernameEdited = false;
        if (widget.initialConnection != null) {
          unawaited(_loadConnectionCredentials(autoConnect: false));
        } else {
          unawaited(restoreCredentials());
        }
      }
    }
  }

  /// Step 26, item 1: the busy episode has run past its ABSOLUTE 30s
  /// deadline (set when the episode started; phase changes do not move
  /// it), so the connect/disconnect attempt is stale. Cancel it on the
  /// native side (stop() cancels a pending connect or disconnects a live
  /// session) and, if the native side never reports back, force the Dart
  /// state to 'failed' so the spinner goes away and the user gets the
  /// form with a "Kết nối lại" button instead of an endless spinner. A
  /// late native event after this is harmless: 'disconnected' matches,
  /// and a late 'connected' cannot happen here because stop() sets
  /// stopping=true and OnConnectionSuccess refuses to report 'connected'
  /// while stopping. The deadline is cleared so a later busy episode
  /// arms a fresh timer.
  Future<void> _onBusyTimeout() async {
    _busyWatchdog = null;
    _busySince = null;
    if (!mounted) return;
    final state = controller.value['state'];
    if (state != 'connecting' && state != 'disconnecting') return;
    debugPrint('AceRdp: busy state "$state" stuck >30s, forcing disconnect');
    await disconnect();
    if (!mounted) return;
    final after = controller.value['state'];
    if (after == 'connecting' || after == 'disconnecting') {
      controller.value = {
        'state': 'failed',
        'error': 'Kết nối quá lâu, đã hủy. Hãy bấm Kết nối lại.',
      };
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Step 26, item 1: returning from the background is when a dropped
    // session must come back by itself. _RemotePageState._resumeRdp()
    // only re-queries the native status (it never reconnects), so this
    // pane — which owns the saved credentials and connect() — does the
    // real work here.
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeReconnect());
    }
  }

  /// Step 26, item 1: reconnect for real after returning from the
  /// background. If the session is still healthy ('connected') do
  /// nothing; otherwise kill the stale attempt (if any) and start one
  /// fresh connect with the saved credentials, so the desktop comes
  /// back without the user tapping anything. At most one fresh connect
  /// per resume; a failure ends on the form with a "Kết nối lại"
  /// button (no loop). Never runs for a page that never connected, or
  /// after the user tapped "Ngắt" (see _cancelConnect).
  Future<void> _resumeReconnect() async {
    if (!mounted || _resumeReconnectRunning) return;
    if (controller.isConnected) return;
    if (!_resumeReconnectArmed) return;
    _resumeReconnectRunning = true;
    try {
      final state = controller.value['state'];
      if (state == 'connecting' || state == 'disconnecting') {
        // A stale attempt is still running (FreeRDP auto-reconnect
        // loop). Stop it first: the native 'connect' call refuses while
        // attempt != null ("Phiên trước chưa kết thúc").
        await disconnect();
        // Wait for the native side to settle (attempt freed) before
        // starting a fresh connect; at most ~5s.
        var settled = false;
        for (var i = 0; i < 25; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!mounted) return;
          final s = await controller.status();
          final st = s?['state'];
          if (st != 'connecting' && st != 'disconnecting') {
            settled = true;
            break;
          }
        }
        if (!settled) {
          // The old session is wedged; do not pile a new connect on
          // top of it (native would reject it as "busy"). Leave the
          // form so the user can tap "Kết nối lại".
          if (mounted) {
            setState(() => localError =
                'Phiên cũ chưa kết thúc. Hãy bấm Kết nối lại.');
          }
          return;
        }
      }
      if (!mounted) return;
      // Refill the form from the saved credentials (the 'disconnected'
      // event already refills via connectionChanged, but reload
      // explicitly so the fields are filled even if that event was
      // lost while the app was in the background).
      if (widget.initialConnection != null) {
        await _loadConnectionCredentials(autoConnect: false);
      } else {
        await restoreCredentials();
      }
      if (!mounted) return;
      if (username.text.trim().isEmpty || password.text.isEmpty) return;
      await connect();
    } finally {
      _resumeReconnectRunning = false;
    }
  }

  /// The "Ngắt" button: the user explicitly cancels the connect, so the
  /// resume handler must not auto-reconnect later. (The watchdog's
  /// _onBusyTimeout calls disconnect() directly and does NOT disarm:
  /// a stuck attempt is not the user's choice.)
  Future<void> _cancelConnect() async {
    _resumeReconnectArmed = false;
    await disconnect();
  }

  void queueStorage(Future<void> Function() action) {
    storageQueue = storageQueue.then((_) => action()).catchError((Object error) {
      if (mounted) setState(() => localError = 'Không cập nhật được mật khẩu đã lưu.');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _busyWatchdog?.cancel();
    _busyWatchdog = null;
    _busySince = null;
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
      // 400ms: let the soft keyboard hide and the layout settle so the
      // native session starts with the final SurfaceView size (step 19).
      // Native logs the rest of the connect timing (Log.d AceRdp).
      debugPrint('AceRdp: connect tapped, waiting 400ms for layout');
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
          // Step 23 redesign (04:03): NO buttons on the remote screen at
          // all — no Trackpad/Touch, no Hide/Show keyboard, no Disconnect,
          // no chevron, no "Đã kết nối" pill. The remote screen is just the
          // desktop + the keyboard, nothing blocking the view. Trackpad mode
          // and keyboard visibility are per-connection settings from the
          // Edit screen (applied in initState). Exit with Android Back
          // (RemotePage's PopScope disconnects first).
          return const SizedBox.shrink();
        }
        final busy = submitting || state == 'connecting' || state == 'disconnecting';
        return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(12),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400),
            child: Card(child: Padding(padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (busy) ...[
                  // Step 24, item 5: modern loading — a compact card with a
                  // spinner, the current connect phase, and a quiet text
                  // button to cancel. Same phase text as step 23; 'Ngắt'
                  // still cancels (and so does Android Back).
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5)),
                    const SizedBox(width: 12),
                    Flexible(
                        child: Text(state == 'disconnecting'
                            ? 'Đang ngắt kết nối…'
                            : (status['phase'] == 'auth'
                                ? 'Đang xác thực…'
                                : status['phase'] == 'creating'
                                    ? 'Đang tạo phiên…'
                                    : 'Đang kết nối…'))),
                    const SizedBox(width: 4),
                    TextButton(
                        onPressed:
                            state == 'disconnecting' ? null : _cancelConnect,
                        child: const Text('Ngắt')),
                  ]),
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
