import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'agent.dart';
import 'rdp_connections.dart';
import 'rdp_input.dart';
import 'rdp_surface.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AceApp());
}

const mockMode = bool.fromEnvironment('ACE_MOCK');
const rdpPrototype = bool.fromEnvironment('ACE_RDP');

class AceApp extends StatefulWidget {
  const AceApp({super.key});
  @override
  State<AceApp> createState() => _AceAppState();
}

class _AceAppState extends State<AceApp> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  SharedPreferences? prefs;
  late final Agent agent;
  ThemeMode theme = ThemeMode.system;
  int pollMs = 500;
  bool ready = false;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    WidgetsBinding.instance.addObserver(this);
    agent = Agent(baseUrl: defaultBaseUrl, mock: mockMode);
    load();
  }

  Future<void> load() async {
    try {
      prefs = await SharedPreferences.getInstance();
      agent.baseUrl =
          prefs!.getString('ace_remote_v1_base_url') ?? defaultBaseUrl;
      pollMs = prefs!.getInt('ace_remote_v1_poll_ms') == 1000 ? 1000 : 500;
      theme = ThemeMode
          .values[prefs!.getInt('ace_remote_v1_theme')?.clamp(0, 2) ?? 0];
      if (mounted) {
        setState(() => ready = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          ready = true;
          error =
              'Không mở được kho dữ liệu. Khởi động lại ứng dụng để thử lại.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    }
  }

  Future<void> save() async {
    await prefs?.setString('ace_remote_v1_base_url', agent.baseUrl);
    await prefs?.setInt('ace_remote_v1_poll_ms', pollMs);
    await prefs?.setInt('ace_remote_v1_theme', theme.index);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    WidgetsBinding.instance.removeObserver(this);
    agent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        title: 'Ace Remote',
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        themeMode: theme,
        theme: ThemeData(
            colorSchemeSeed: const Color(0xFF2BB3A3),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFFFF8E6),
            cardColor: Colors.white,
            appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFFFFD93D),
                foregroundColor: Color(0xFF333333))),
        darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF2BB3A3),
            scaffoldBackgroundColor: const Color(0xFF121F1E),
            cardColor: const Color(0xFF1E2E2C),
            appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF1E3A37),
                foregroundColor: Colors.white),
            brightness: Brightness.dark,
            useMaterial3: true),
        home: !ready
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : error != null
                ? Scaffold(
                    appBar: AppBar(title: const Text('Ace Remote')),
                    body: Center(child: Text(error!)))
                : Home(
                    agent: agent,
                    pollMs: () => pollMs,
                    settings: () => SettingsPage(
                        agent: agent,
                        theme: theme,
                        pollMs: pollMs,
                        onSave: (url, mode, ms) async {
                          agent.baseUrl = url;
                          theme = mode;
                          pollMs = ms;
                          await save();
                        })),
      );
}

class Home extends StatefulWidget {
  const Home(
      {super.key,
      required this.agent,
      required this.pollMs,
      required this.settings});
  final Agent agent;
  final int Function() pollMs;
  final Widget Function() settings;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // Step 23, item 6: Home is now the saved-connections list, like the
  // "PC Connections" section of Microsoft Remote Desktop. Tapping a card
  // connects right away with its saved host/port/user/pass; "+" adds a
  // connection. Long-press a card (redesign 04:03) opens a context menu —
  // Connect / Favorite / Edit / Delete, like the sample — and Edit opens a
  // full screen that configures the connection AND its trackpad/keyboard
  // settings. The old single agent card is gone: in the RDP build its
  // "Kết nối" button already opened the RDP page, and the agent address is
  // still editable (and testable) in Settings.
  final _store = RdpConnectionStore();
  List<RdpConnection>? _connections;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final connections = await _store.load();
      if (mounted) {
        setState(() {
          _connections = connections;
          _error = null;
        });
      }
    } catch (_) {
      // Show the list area (empty) instead of spinning forever.
      if (mounted) {
        setState(() {
          _connections = [];
          _error = 'Không mở được danh sách kết nối.';
        });
      }
    }
  }

  void _open(RdpConnection connection) {
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => RemotePage(
                agent: widget.agent,
                pollMs: widget.pollMs,
                settings: widget.settings,
                rdpMode: true,
                rdpConnection: connection)));
  }

  /// Add/edit page: name, host, port, username and password plus the
  /// per-connection trackpad/keyboard settings are configured there
  /// (redesign 04:03 — a full screen, not a dialog). The password field is
  /// prefilled with the saved password when editing, so saving keeps it
  /// unless the user changes it.
  Future<void> _showEditor({RdpConnection? existing}) async {
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
            builder: (_) =>
                _ConnectionEditorPage(existing: existing, store: _store)));
    if (saved == true) await _reload();
  }

  /// Long-press context menu on a card (redesign 04:03, after the Microsoft
  /// Remote Desktop sample): Connect / Favorite / Edit / Delete, each with
  /// an icon + label. Anchored at the card so it opens next to the finger.
  Future<void> _showConnectionMenu(
      BuildContext cardContext, RdpConnection connection) async {
    final box = cardContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(cardContext).context.findRenderObject() as RenderBox?;
    final position = box == null || overlay == null
        ? const RelativeRect.fromLTRB(0, 0, 0, 0)
        : RelativeRect.fromRect(
            box.localToGlobal(Offset.zero) & box.size,
            Offset.zero & overlay.size);
    final choice = await showMenu<String>(
        context: cardContext,
        position: position,
        items: [
          const PopupMenuItem(
              value: 'connect',
              child: Row(children: [
                Icon(Icons.play_circle_outline),
                SizedBox(width: 12),
                Text('Connect'),
              ])),
          PopupMenuItem(
              value: 'favorite',
              child: Row(children: [
                Icon(connection.favorite
                    ? Icons.star
                    : Icons.star_outline),
                const SizedBox(width: 12),
                Text(connection.favorite ? 'Bỏ yêu thích' : 'Favorite'),
              ])),
          const PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_outlined),
                SizedBox(width: 12),
                Text('Edit'),
              ])),
          const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline),
                SizedBox(width: 12),
                Text('Delete'),
              ])),
        ]);
    switch (choice) {
      case 'connect':
        _open(connection);
      case 'favorite':
        await _store.update(connection.copyWith(favorite: !connection.favorite));
        await _reload();
      case 'edit':
        await _showEditor(existing: connection);
      case 'delete':
        await _confirmDelete(connection);
    }
  }

  Future<void> _confirmDelete(RdpConnection connection) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Xóa kết nối?'),
                content: Text(
                    'Xóa "${connection.name}" (${connection.address})? Mật khẩu đã lưu của kết nối này cũng bị xóa.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Hủy')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Xóa')),
                ]));
    if (confirmed == true) {
      await _store.remove(connection.id);
      await _reload();
    }
  }

  Widget _connectionCard(RdpConnection connection) => Builder(
      builder: (cardContext) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: () => _open(connection),
          // Redesign 04:03: hold the card to open the Connect / Favorite /
          // Edit / Delete menu (like the Microsoft Remote Desktop sample);
          // the card itself stays clean, with no buttons on it.
          onLongPress: () => _showConnectionMenu(cardContext, connection),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Device-card header (step 23, after the Microsoft Remote
                // Desktop sample): a gradient band in the app teal/blue
                // with the machine name on it, like the sample's device
                // card with its Windows 11 wallpaper header.
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xff1d7f73), Color(0xff2b6cb0)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(connection.name,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white))),
                            if (connection.favorite)
                              const Icon(Icons.star,
                                  size: 20, color: Colors.amber),
                          ]),
                          Text(connection.address,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white70)),
                        ])),
                Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(children: [
                      const Icon(Icons.person_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(connection.username.isEmpty
                              ? 'Chưa có tài khoản — bấm để nhập'
                              : connection.username)),
                    ])),
              ]))));

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Ace Remote'), actions: [
        IconButton(
            tooltip: 'Thêm kết nối',
            icon: const Icon(Icons.add),
            onPressed: () => _showEditor()),
        IconButton(
            tooltip: 'Cài đặt',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute<void>(builder: (_) => widget.settings()));
            })
      ]),
      body: _connections == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (widget.agent.mock)
                const Text('CHẾ ĐỘ MÔ PHỎNG • Không gửi lệnh tới PC'),
              // Section header, like the sample's "PC Connections".
              const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Text('Kết nối đã lưu',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600))),
              if (_connections!.isEmpty)
                const Card(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                            'Chưa có kết nối nào. Bấm + để thêm kết nối mới.'))),
              for (final connection in _connections!)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _connectionCard(connection)),
              if (_error != null) Text(_error!),
            ]));
}

/// Add/edit connection page (step 23 redesign, 04:03 — a full screen, not a
/// dialog). Configures the connection (name, host, port, username, password)
/// AND its per-connection settings: trackpad mode and keyboard visibility.
/// While the saved password is still loading for an edit, Save stays
/// disabled so it cannot blank the stored password.
class _ConnectionEditorPage extends StatefulWidget {
  const _ConnectionEditorPage({this.existing, required this.store});
  final RdpConnection? existing;
  final RdpConnectionStore store;
  @override
  State<_ConnectionEditorPage> createState() => _ConnectionEditorPageState();
}

class _ConnectionEditorPageState extends State<_ConnectionEditorPage> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final host = TextEditingController(text: widget.existing?.host ?? '');
  late final port = TextEditingController(
      text: widget.existing == null ? '3389' : widget.existing!.port.toString());
  late final username =
      TextEditingController(text: widget.existing?.username ?? '');
  late final password = TextEditingController();
  late bool trackpadMode = widget.existing?.trackpadMode ?? false;
  late bool keyboardVisible = widget.existing?.keyboardVisible ?? true;
  String? error;
  bool loadingPassword = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      loadingPassword = true;
      widget.store.passwordFor(widget.existing!.id).then((saved) {
        if (mounted) {
          setState(() {
            password.text = saved;
            loadingPassword = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    for (final field in [name, host, port, username, password]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final portNumber = int.tryParse(port.text.trim());
    if (name.text.trim().isEmpty ||
        host.text.trim().isEmpty ||
        portNumber == null ||
        portNumber < 1 ||
        portNumber > 65535) {
      setState(() => error = 'Nhập đủ tên, host và port (1–65535).');
      return;
    }
    final existing = widget.existing;
    if (existing == null) {
      await widget.store.add(
          name: name.text.trim(),
          host: host.text.trim(),
          port: portNumber,
          username: username.text.trim(),
          password: password.text,
          trackpadMode: trackpadMode,
          keyboardVisible: keyboardVisible);
    } else {
      await widget.store.update(
          existing.copyWith(
              name: name.text.trim(),
              host: host.text.trim(),
              port: portNumber,
              username: username.text.trim(),
              trackpadMode: trackpadMode,
              keyboardVisible: keyboardVisible),
          password: password.text);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null ? 'Thêm kết nối' : 'Sửa kết nối')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            key: const ValueKey('connection-name'),
            controller: name,
            decoration: const InputDecoration(labelText: 'Tên hiển thị'),
            textCapitalization: TextCapitalization.words),
        TextField(
            key: const ValueKey('connection-host'),
            controller: host,
            decoration:
                const InputDecoration(labelText: 'Host (IP hoặc tên máy)'),
            keyboardType: TextInputType.url),
        TextField(
            key: const ValueKey('connection-port'),
            controller: port,
            decoration: const InputDecoration(labelText: 'Port'),
            keyboardType: TextInputType.number),
        TextField(
            key: const ValueKey('connection-username'),
            controller: username,
            decoration: const InputDecoration(labelText: 'Username')),
        TextField(
            key: const ValueKey('connection-password'),
            controller: password,
            decoration: const InputDecoration(labelText: 'Mật khẩu'),
            obscureText: true),
        const SizedBox(height: 16),
        SwitchListTile(
            title: const Text('Chế độ Trackpad'),
            subtitle: const Text(
                'Bật: lướt trên bàn phím để di chuột. Tắt: chạm trực tiếp vào màn hình.'),
            value: trackpadMode,
            onChanged: (v) => setState(() => trackpadMode = v)),
        SwitchListTile(
            title: const Text('Hiện bàn phím'),
            subtitle: const Text(
                'Tắt: màn hình remote chiếm toàn bộ màn hình khi kết nối.'),
            value: keyboardVisible,
            onChanged: (v) => setState(() => keyboardVisible = v)),
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!,
                  style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: loadingPassword ? null : _save,
            child: const Text('Lưu')),
      ]));
}

String clean(Object e) {
  if (e is FormatException) {
    return 'Sai địa chỉ hoặc dữ liệu agent không hợp lệ.';
  }
  final message = e.toString();
  return message.startsWith('Exception: ')
      ? message.substring(11)
      : 'Lỗi kết nối hoặc dữ liệu không hợp lệ. Hãy thử lại.';
}

class SettingsPage extends StatefulWidget {
  const SettingsPage(
      {super.key,
      required this.agent,
      required this.theme,
      required this.pollMs,
      required this.onSave});
  final Agent agent;
  final ThemeMode theme;
  final int pollMs;
  final Future<void> Function(String, ThemeMode, int) onSave;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final url = TextEditingController(text: widget.agent.baseUrl);
  late ThemeMode mode = widget.theme;
  late int ms = widget.pollMs;
  String message = '';
  bool busy = false;
  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: url,
            decoration:
                const InputDecoration(labelText: 'Địa chỉ agent (Base URL)'),
            keyboardType: TextInputType.url),
        OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    final probe = Agent(
                        baseUrl: url.text.trim(), mock: widget.agent.mock);
                    try {
                      await probe.health();
                      if (mounted) {
                        setState(
                            () => message = 'Kết nối thành công (/health)');
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() => message = clean(e));
                      }
                    } finally {
                      probe.dispose();
                      if (mounted) {
                        setState(() => busy = false);
                      }
                    }
                  },
            child: const Text('Kiểm tra kết nối')),
        Text(message),
        DropdownButtonFormField<ThemeMode>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'Giao diện'),
            items: const [
              DropdownMenuItem(
                  value: ThemeMode.system, child: Text('Theo điện thoại')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Sáng')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Tối'))
            ],
            onChanged: (v) => setState(() => mode = v!)),
        DropdownButtonFormField<int>(
            initialValue: ms,
            decoration: const InputDecoration(labelText: 'Tốc độ ảnh'),
            items: const [
              DropdownMenuItem(
                  value: 500, child: Text('Bình thường • 2 ảnh/giây')),
              DropdownMenuItem(
                  value: 1000, child: Text('Tiết kiệm • 1 ảnh/giây'))
            ],
            onChanged: (v) => setState(() => ms = v!)),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
                'Máy ngủ hẳn thì không gọi dậy được ở v1.\nAgent PC cần mở binding trên IP Tailscale; hiện tại chỉ nghe 127.0.0.1.\nChỉ kết nối agent của bạn trong tailnet tin cậy.')),
        FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final probe = Agent(baseUrl: url.text.trim());
                    try {
                      probe.uri('/health');
                      await widget.onSave(url.text.trim(), mode, ms);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      setState(() => message = clean(e));
                    } finally {
                      probe.dispose();
                    }
                  },
            child: const Text('Lưu cài đặt')),
      ]));
}

class RemotePage extends StatefulWidget {
  const RemotePage(
      {super.key,
      required this.agent,
      required this.pollMs,
      this.settings,
      this.rdpConnection,
      this.rdpMode = rdpPrototype});
  final Widget Function()? settings;
  final bool rdpMode;
  // Step 23, item 6: the saved connection tapped on Home; its host/port and
  // stored user/pass are used to connect right away.
  final RdpConnection? rdpConnection;
  final Agent agent;
  final int Function() pollMs;
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
  Agent get agent => widget.agent;
  ui.Image? frame;
  double fitScale = 1;
  String? pressedLabel;
  String? failedPath;
  Map<String, dynamic>? failedData;
  Size imageSize = const Size(1, 1);
  final transform = TransformationController();
  Timer? timer;
  bool running = true,
      polling = false,
      relative = false,
      keyboard = true,
      overlay = true;
  int monitor = 1, failures = 0, delay = 500;
  String? error;
  bool controlsHealthy = true;
  Offset cursor = Offset.zero;
  final rdpController = RdpController();
  Future<void> rdpQueue = Future.value();
  final Set<String> modifiers = {};
  // Caps Lock state tracked by the app: toggled on each Caps press. The
  // server flips its own Caps Lock state on every VK_CAPITAL press, so this
  // stays in sync as long as Caps is only pressed from this on-screen
  // keyboard; pressing Caps Lock on a physical keyboard will not update it.
  bool capsLockOn = false;
  // Swipe-to-move on the RDP keyboard (step 23): a drag across the keys
  // moves the cursor relatively instead of typing; a quick tap still types
  // the key. Works in both touch and trackpad modes so the mouse is always
  // reachable from the keyboard. kbSuppressKey tells press() to ignore the
  // tap that ends a swipe / two-finger gesture (the tap recognizer may
  // still fire for short drags); it is cleared on the next pointer down.
  final Map<int, Offset> kbSwipePoints = {};
  double kbSwipeDistance = 0;
  int kbSwipeDownTime = 0;
  bool kbSwipeTwoFinger = false;
  double kbSwipeScrollAccum = 0;
  double kbSwipeTwoFingerTravel = 0;
  Offset kbSwipeTwoFingerCenter = Offset.zero;
  bool kbSuppressKey = false;
  Future<void> queue = Future.value();
  int pending = 0;
  int commandEpoch = 0;
  bool dragging = false;
  void releaseDrag() {
    if (!dragging) {
      return;
    }
    dragging = false;
    unawaited(agent.command('/click', {
      'button': 'left',
      'action': 'up',
      'monitor': monitor
    }).catchError((Object _) {}));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (agent.displays.isNotEmpty) {
      final first = agent.displays.first;
      monitor = first.id;
    }
    cursor = agent.cursor ?? agent.virtualOrigin;
    poll();
  }

  DisplayInfo? get display {
    for (final d in agent.displays) {
      if (d.id == monitor) {
        return d;
      }
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    running = state == AppLifecycleState.resumed;
    if (!running) {
      commandEpoch++;
      releaseDrag();
    }
    timer?.cancel();
    if (running) {
      poll();
    }
  }

  Future<void> poll() async {
    if (widget.rdpMode || !mounted || !running || polling) {
      return;
    }
    polling = true;
    final requestedMonitor = monitor;
    try {
      final bytes = await agent.screenshot(display?.screenshotIndex ?? 0);
      final codec = await ui.instantiateImageCodec(bytes);
      final decoded = await codec.getNextFrame();
      final size =
          Size(decoded.image.width.toDouble(), decoded.image.height.toDouble());
      codec.dispose();
      if (mounted && running && requestedMonitor == monitor) {
        setState(() {
          frame?.dispose();
          frame = decoded.image;
          imageSize = size;
          failures = 0;
        });
      } else {
        decoded.image.dispose();
      }
    } catch (_) {
      failures++;
    } finally {
      polling = false;
      delay = failures == 0
          ? 0
          : min(8000, widget.pollMs() * (1 << min(failures, 4)));
      if (mounted && running) {
        timer = Timer(Duration(milliseconds: delay), poll);
      }
    }
  }

  Future<void> send(String path, Map<String, dynamic> data) {
    if (!controlsHealthy) {
      return Future.value();
    }
    if (pending >= 48 && (path == '/move' || path == '/scroll')) {
      return Future.value();
    }
    pending++;
    final epoch = commandEpoch;
    final targetMonitor = data['monitor'] ?? monitor;
    queue = queue.then((_) async {
      if (!mounted || !running || !controlsHealthy || epoch != commandEpoch) {
        return;
      }
      try {
        await agent.command(path, {
          ...data,
          if (path == '/key' && data['key'] is String)
            'keys': sendKeysChord(data['key'] as String),
          if (path != '/power') 'monitor': targetMonitor,
        });
      } catch (e) {
        if (mounted) {
          setState(() {
            error = 'Lệnh điều khiển bị gián đoạn. ${clean(e)}';
            failedPath = path;
            failedData = {...data, 'monitor': targetMonitor};
            controlsHealthy = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 10),
            content: Text(error!),
            action: SnackBarAction(
                label: 'Thử lại',
                onPressed: () async {
                  final path = failedPath;
                  final data = failedData;
                  if (path == null || data == null) return;
                  setState(() {
                    error = null;
                    controlsHealthy = true;
                  });
                  await send(path, data);
                }),
          ));
        }
      }
    }).whenComplete(() => pending--);
    return queue;
  }

  Future<void> key(String k) async {
    final combo = [...modifiers, k].join('+');
    setState(() => modifiers.clear());
    await send('/key', {'key': combo});
  }

  Future<void> typeText(String value) async {
    if (value.isEmpty) {
      return;
    }
    await send('/type', {'text': value});
  }

  void click(String button, [Offset? at]) {
    if (at != null) {
      cursor = at;
    }
    send('/click',
        {'button': button, 'x': cursor.dx.round(), 'y': cursor.dy.round()});
  }

  void move(Offset delta) {
    // The real agent accepts absolute x/y, never relative dx/dy.
    final d = display;
    final origin = d == null
        ? agent.virtualOrigin
        : Offset(d.x.toDouble(), d.y.toDouble());
    final size = d == null
        ? agent.virtualSize
        : Size(d.width.toDouble(), d.height.toDouble());
    cursor = Offset(
        (cursor.dx + delta.dx).clamp(origin.dx, origin.dx + size.width - 1),
        (cursor.dy + delta.dy).clamp(origin.dy, origin.dy + size.height - 1));
    send('/move', {'x': cursor.dx.round(), 'y': cursor.dy.round()});
  }

  void notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
          context: context,
          builder: (c) =>
              AlertDialog(title: Text(title), content: Text(body), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Hủy')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Xác nhận'))
              ])) ??
      false;
  Future<void> power(String action) async {
    final label = {
      'shutdown': 'Tắt máy',
      'restart': 'Khởi động lại',
      'sleep': 'Ngủ'
    }[action]!;
    if (action != 'sleep') {
      if (!await confirm(label, 'Bạn muốn $label PC ace?')) {
        return;
      }
      if (!mounted ||
          !await confirm('Xác nhận lần 2',
              'Hãy lưu công việc trên PC. Tiếp tục $label?')) {
        return;
      }
    } else if (!await confirm(
        label, 'Máy ngủ sẽ không gọi dậy được từ app v1. Tiếp tục?')) {
      return;
    }
    await send('/power', {'action': action});
    if (controlsHealthy) {
      notice('Đã gửi lệnh ${label.toLowerCase()}');
    }
  }

  @override
  void dispose() {
    running = false;
    commandEpoch++;
    releaseDrag();
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    frame?.dispose();
    transform.dispose();
    rdpController.dispose();
    super.dispose();
  }

  Widget screenshot() => LayoutBuilder(builder: (context, box) {
        if (frame == null) {
          return const Center(child: Text('Đang lấy ảnh…'));
        }
        final d = display;
        final source = Offset.zero & imageSize;
        final scale = box.maxWidth / source.width;
        fitScale = scale;
        final fitted = Size(source.width * scale, source.height * scale);
        return ClipRect(
            child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.center,
          child: SizedBox(
              width: fitted.width,
              height: fitted.height,
              child: Stack(children: [
                InteractiveViewer(
                  transformationController: transform,
                  minScale: 0.5,
                  maxScale: max(8, 1 / scale),
                  child: GestureDetector(
                      onTapUp: relative
                          ? null
                          : (details) {
                              if (d != null) {
                                click('left',
                                    d.map(details.localPosition, fitted));
                              }
                            },
                      child: CustomPaint(
                          size: fitted,
                          painter: RemoteFramePainter(frame!, source))),
                ),
                if (relative && overlay)
                  Positioned.fill(child: trackpad(translucent: true)),
              ])),
        ));
      });

  Widget trackpad({bool translucent = false, Widget? child}) => LayoutBuilder(
      builder: (context, box) => KeyboardSurface(
            keyAt: child == null ? null : keyAt,
            onMove: (delta) {
              if (widget.rdpMode) return;
              final d = display;
              final size = d == null
                  ? agent.virtualSize
                  : Size(d.width.toDouble(), d.height.toDouble());
              move(Offset(delta.dx * size.width / box.maxWidth,
                  delta.dy * size.height / box.maxHeight));
            },
            onPressed: child == null
                ? null
                : (position) {
                    String? label;
                    if (position != null) {
                      for (final entry in keyLabels.entries) {
                        final box =
                            entry.key.currentContext?.findRenderObject();
                        if (box is RenderBox &&
                            box.hasSize &&
                            (box.localToGlobal(Offset.zero) & box.size)
                                .contains(position)) {
                          label = entry.value;
                          break;
                        }
                      }
                    }
                    if (mounted) setState(() => pressedLabel = label);
                  },
            onClick: (button) {
              if (!widget.rdpMode) click(button);
            },
            onScroll: (dy) {
              if (!widget.rdpMode) {
                send('/scroll', {'delta': (-dy * 3).round()});
              }
            },
            onDrag: (down) {
              if (widget.rdpMode) return;
              if (!agent.capabilities.contains('mouse_drag')) {
                if (down) {
                  notice('Agent không có mouse_drag (down/up).');
                }
                return;
              }
              dragging = down;
              send(
                  '/click', {'button': 'left', 'action': down ? 'down' : 'up'});
            },
            child: child,
          ));
  final keyLabels = <GlobalKey, String>{};
  final keyTargets = <GlobalKey, VoidCallback>{};

  VoidCallback? keyAt(Offset position) {
    for (final entry in keyTargets.entries) {
      final box = entry.key.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).contains(position)) {
        return entry.value;
      }
    }
    return null;
  }

  void rdpKey(String key) {
    if (!rdpController.isConnected) return;
    // Caps Lock is a real toggle: one VK_CAPITAL press flips the Windows
    // Caps Lock state. It is NOT a one-shot modifier, so it never joins
    // `modifiers` and is never cleared after the next key.
    if (key == 'Caps') {
      final vk = rdpVirtualKey(key);
      if (vk == null) return;
      setState(() => capsLockOn = !capsLockOn);
      rdpQueue = rdpQueue.then((_) async {
        await rdpController.sendKey(vk, true);
        await rdpController.sendKey(vk, false);
      });
      return;
    }
    final vk = rdpVirtualKey(key);
    if (vk == null) return;
    if (const ['Win', 'Ctrl', 'Alt', 'Shift'].contains(key)) {
      final wasArmed = modifiers.contains(key);
      setState(() {
        wasArmed ? modifiers.remove(key) : modifiers.add(key);
      });
      if (key != 'Win' || !wasArmed) return;
      rdpQueue = rdpQueue.then((_) async {
        await rdpController.sendKey(vk, true);
        await rdpController.sendKey(vk, false);
      });
      return;
    }
    final armed = [
      for (final m in ['Win', 'Ctrl', 'Alt', 'Shift'])
        if (modifiers.contains(m)) rdpVirtualKey(m)!
    ];
    setState(() => modifiers.clear());
    rdpQueue = rdpQueue.then((_) async {
      for (final m in armed) {
        await rdpController.sendKey(m, true);
      }
      await rdpController.sendKey(vk, true);
      await rdpController.sendKey(vk, false);
      for (final m in armed.reversed) {
        await rdpController.sendKey(m, false);
      }
    });
  }

  Widget laptopKey(String label,
      {double units = 1, String? command, bool modifier = false}) {
    final isCaps = label == 'Caps';
    // In RDP mode the Caps key shows the app-tracked Caps Lock state; in
    // agent mode Caps still arms Shift one-shot, so it highlights while
    // Shift is armed, as before.
    final selected = modifier &&
        (isCaps
            ? (widget.rdpMode ? capsLockOn : modifiers.contains('Shift'))
            : modifiers.contains(command ?? label));
    void press() {
      if (widget.rdpMode) {
        // A swipe / two-finger gesture on the keyboard must not type a key.
        if (kbSuppressKey) { kbSuppressKey = false; return; }
        // Caps must reach rdpKey as 'Caps' (a real Caps Lock toggle), even
        // though this widget carries command 'Shift' for agent mode.
        rdpKey(isCaps ? 'Caps' : (command ?? label));
        return;
      }
      if (label == 'Click trái' || label == 'Click phải') {
        setState(() => modifiers.clear());
        click(label == 'Click trái' ? 'left' : 'right');
      } else if (modifier && label == 'Win') {
        if (modifiers.contains('Win')) {
          setState(() => modifiers.remove('Win'));
          key('Win');
        } else {
          setState(() => modifiers.add('Win'));
        }
      } else if (modifier) {
        setState(() {
          modifiers.contains(command ?? label)
              ? modifiers.remove(command ?? label)
              : modifiers.add(command ?? label);
        });
      } else if (command != null) {
        key(command);
      } else if (modifiers.isEmpty) {
        typeText(label.toLowerCase());
      } else {
        key(label.toUpperCase());
      }
    }

    final target = GlobalKey();
    keyTargets[target] = press;
    keyLabels[target] = label;
    return Expanded(
        flex: (units * 100).round(),
        child: Padding(
            padding: const EdgeInsets.all(2),
            child: Semantics(
                button: true,
                selected: selected,
                label: label,
                onTap: press,
                child: Container(
                    key: target,
                    decoration: BoxDecoration(
                        // Modern key look (step 23): larger radius, lighter
                        // key surface with a softer border; an armed
                        // modifier / Caps Lock on uses the app teal accent.
                        color: pressedLabel == label
                            ? const Color(0xff8b929e)
                            : selected
                                ? const Color(0xff2bb3a3)
                                : const Color(0xff32353c),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xff4a4d55))),
                    child: Center(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(label,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white)))))))));
  }

  Widget keyboardPanel() => LayoutBuilder(builder: (context, box) {
        keyTargets.clear();
        keyLabels.clear();
        Widget row(int index, List<Widget> keys, {int flex = 1}) => Expanded(
            flex: flex,
            child: Row(key: ValueKey('keyboard-row-$index'), children: keys));
        return Padding(
            padding: const EdgeInsets.all(4),
            child: trackpad(
                child: Column(children: [
              row(0, [
                laptopKey('Esc', command: 'Esc'),
                for (var i = 1; i <= 12; i++) laptopKey('F$i', command: 'F$i'),
                laptopKey('Del', command: 'Delete'),
              ]),
              row(1, [
                for (final c in '`1234567890-='.split('')) laptopKey(c),
                laptopKey('Backspace', units: 2, command: 'Backspace'),
              ]),
              row(2, [
                laptopKey('Tab', units: 1.5, command: 'Tab'),
                for (final c in 'QWERTYUIOP[]'.split('')) laptopKey(c),
                laptopKey(r'\', units: 1.5),
              ]),
              row(3, [
                laptopKey('Caps',
                    units: 1.75, command: 'Shift', modifier: true),
                for (final c in "ASDFGHJKL;'".split('')) laptopKey(c),
                laptopKey('Enter', units: 2.25, command: 'Enter'),
              ]),
              row(4, [
                laptopKey('Shift',
                    units: 2.25, command: 'Shift', modifier: true),
                for (final c in 'ZXCVBNM,./'.split('')) laptopKey(c),
                laptopKey('Shift',
                    units: 2.75, command: 'Shift', modifier: true),
              ]),
              row(5, [
                laptopKey('Ctrl', units: 1.25, modifier: true),
                laptopKey('Win', units: 1.25, modifier: true),
                laptopKey('Alt', units: 1.25, modifier: true),
                laptopKey('Space', units: 5, command: 'Space'),
                laptopKey('Alt', units: 1.25, modifier: true),
                laptopKey('Ctrl', units: 1.25, modifier: true),
                for (final e in const {
                  '←': 'Left',
                  '↑': 'Up',
                  '↓': 'Down',
                  '→': 'Right'
                }.entries)
                  laptopKey(e.key, command: e.value),
              ]),
              if (!widget.rdpMode)
                row(6, [laptopKey('Click trái'), laptopKey('Click phải')],
                    flex: 2),
            ])));
      });

  /// Swipe-to-move wrapper for the RDP keyboard (step 23). The keyboard
  /// stays visible in both touch and trackpad modes; a drag across the keys
  /// (more than 12 logical px) moves the cursor relatively and suppresses
  /// the key under the finger, a quick tap still types the key, a
  /// two-finger tap clicks right, and a two-finger drag scrolls (one notch
  /// per 48 logical px). Deltas are reported in surface physical pixels
  /// (logical px x devicePixelRatio); native converts them to framebuffer
  /// pixels with the trackpad sensitivity. This is a Listener, not a
  /// gesture detector, so key taps keep working: the tap recognizer fires
  /// press() only for real taps, and kbSuppressKey covers the short drags
  /// that still count as taps.
  Widget keyboardSwipe(Widget child) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        kbSuppressKey = false;
        if (kbSwipePoints.isEmpty) {
          kbSwipeDistance = 0;
          kbSwipeTwoFinger = false;
          kbSwipeScrollAccum = 0;
          kbSwipeTwoFingerTravel = 0;
          kbSwipeDownTime = e.timeStamp.inMilliseconds;
        }
        kbSwipePoints[e.pointer] = e.localPosition;
        if (kbSwipePoints.length == 2) {
          kbSwipeTwoFinger = true;
          kbSwipeTwoFingerCenter =
              (kbSwipePoints.values.first + kbSwipePoints.values.last) / 2;
          kbSwipeScrollAccum = 0;
          kbSwipeTwoFingerTravel = 0;
          // Two fingers on keys must not type either key.
          kbSuppressKey = true;
        }
      },
      onPointerMove: (e) {
        final old = kbSwipePoints[e.pointer];
        if (old == null) return;
        final delta = e.localPosition - old;
        kbSwipePoints[e.pointer] = e.localPosition;
        if (kbSwipePoints.length == 2) {
          final center =
              (kbSwipePoints.values.first + kbSwipePoints.values.last) / 2;
          final centerDelta = center - kbSwipeTwoFingerCenter;
          kbSwipeTwoFingerCenter = center;
          kbSwipeTwoFingerTravel += centerDelta.distance;
          kbSwipeScrollAccum += centerDelta.dy;
          while (kbSwipeScrollAccum.abs() >= 48) {
            unawaited(rdpController.scrollWheel(kbSwipeScrollAccum > 0));
            kbSwipeScrollAccum += kbSwipeScrollAccum > 0 ? -48 : 48;
          }
        } else if (kbSwipePoints.length == 1 && !kbSwipeTwoFinger) {
          kbSwipeDistance += delta.distance;
          if (kbSwipeDistance > 12) {
            kbSuppressKey = true;
            unawaited(rdpController.moveRelative(delta * dpr));
          }
        }
      },
      onPointerUp: (e) {
        kbSwipePoints.remove(e.pointer);
        if (kbSwipePoints.isEmpty) {
          final duration = e.timeStamp.inMilliseconds - kbSwipeDownTime;
          if (kbSwipeTwoFinger) {
            if (kbSwipeTwoFingerTravel < 48 &&
                kbSwipeScrollAccum.abs() < 48 &&
                duration < 500) {
              unawaited(rdpController.clickAtLastPosition('right'));
            }
          }
          kbSwipeTwoFinger = false;
          kbSwipeDistance = 0;
          kbSwipeScrollAccum = 0;
          kbSwipeTwoFingerTravel = 0;
        }
      },
      onPointerCancel: (_) {
        kbSwipePoints.clear();
        kbSwipeTwoFinger = false;
        kbSwipeDistance = 0;
        kbSwipeScrollAccum = 0;
        kbSwipeTwoFingerTravel = 0;
      },
      child: child,
    );
  }

  Widget laptopDeck(Widget child) {
    return Theme(
        data: ThemeData.dark(useMaterial3: true),
        child: ColoredBox(color: const Color(0xff16171a), child: child));
  }

  void showLog() => showModalBottomSheet<void>(
      context: context,
      builder: (_) => ValueListenableBuilder<List<String>>(
          valueListenable: agent.log,
          builder: (_, entries, __) =>
              ListView(padding: const EdgeInsets.all(12), children: [
                const Text('Nhật ký mock (100 lệnh gần nhất)'),
                ...entries.reversed.map((e) => SelectableText(e))
              ])));
  Future<void> menuAction(String action) async {
    if (action.startsWith('monitor:')) {
      final id = int.parse(action.substring(8));
      final d = agent.displays.firstWhere((d) => d.id == id);
      releaseDrag();
      setState(() {
        monitor = id;
        frame?.dispose();
        frame = null;
        transform.value = Matrix4.identity();
        cursor = Offset(d.x + d.width / 2, d.y + d.height / 2);
      });
      timer?.cancel();
      poll();
    } else if (action == 'fit') {
      transform.value = Matrix4.identity();
    } else if (action == 'actual') {
      transform.value = Matrix4.diagonal3Values(1 / fitScale, 1 / fitScale, 1);
    } else if (action == 'relative') {
      releaseDrag();
      setState(() => relative = !relative);
    } else if (action == 'overlay') {
      releaseDrag();
      setState(() {
        overlay = !overlay;
        if (overlay) relative = true;
      });
    } else if (action == 'keyboard') {
      releaseDrag();
      setState(() => keyboard = !keyboard);
    } else if (action == 'log') {
      showLog();
    } else if (action == 'settings') {
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) =>
                  widget.settings?.call() ??
                  SettingsPage(
                      agent: agent,
                      theme: ThemeMode.system,
                      pollMs: widget.pollMs(),
                      onSave: (url, mode, ms) async {
                        agent.baseUrl = url;
                      })));
      if (mounted) {
        try {
          await agent.health();
        } catch (e) {
          notice(clean(e));
        }
      }
    } else if (action == 'disconnect') {
      Navigator.pop(context);
    } else {
      await power(action);
    }
  }

  @override
  // Step 23 redesign (04:03): the remote screen has no buttons at all, so
  // Android Back (or the swipe-back gesture) is the way out: it disconnects
  // the RDP session (in RDP mode) and returns to Home. canPop stays true so
  // Back never gets stuck, and never exits the app by itself (Home is
  // underneath this route).
  Widget build(BuildContext context) => PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && widget.rdpMode) {
          unawaited(rdpController.disconnect());
        }
      },
      child: Scaffold(
        body: LayoutBuilder(builder: (context, box) {
          if (widget.rdpMode) {
            // The bottom half is always the keyboard: in trackpad mode the
            // keys stay visible and a swipe across them moves the cursor
            // (step 23), so the mouse is reachable without losing the keys.
            // The keyboard can be hidden entirely so the remote screen
            // fills the whole page. Switching never drops the RDP session
            // and never resets the cursor.
            return ValueListenableBuilder<bool>(
              valueListenable: rdpController.keyboardVisible,
              builder: (context, kbVisible, _) => Column(children: [
                Expanded(
                    child: SizedBox(
                        key: const ValueKey('remote-half'),
                        child: RdpConnectionPane(
                            controller: rdpController,
                            initialConnection: widget.rdpConnection))),
                if (kbVisible)
                  Expanded(
                      child: SizedBox(
                          key: const ValueKey('keyboard-half'),
                          child:
                              laptopDeck(keyboardSwipe(keyboardPanel())))),
              ]),
            );
          }
          final d = display;
          final size = d == null
              ? agent.virtualSize
              : Size(d.width.toDouble(), d.height.toDouble());
          final imageHeight = box.maxWidth * size.height / size.width;
          final content = SizedBox(
              height: max(box.maxHeight, imageHeight + 80),
              child: Column(children: [
                SizedBox(
                    height: imageHeight,
                    child: Stack(key: const ValueKey('remote-half'), children: [
                      Positioned.fill(child: screenshot()),
                      Positioned(
                          top: 0,
                          right: 0,
                          child: SafeArea(
                              bottom: false,
                              child: PopupMenuButton<String>(
                                tooltip: 'Điều khiển',
                                icon: const Icon(Icons.more_vert,
                                    color: Colors.white),
                                color: Theme.of(context).colorScheme.surface,
                                onSelected: menuAction,
                                itemBuilder: (_) => [
                                  for (final d in agent.displays)
                                    CheckedPopupMenuItem(
                                        value: 'monitor:${d.id}',
                                        checked: d.id == monitor,
                                        child: Text('Màn hình ${d.id}')),
                                  const PopupMenuItem(
                                      value: 'fit',
                                      child: Text('Vừa màn hình')),
                                  const PopupMenuItem(
                                      value: 'actual', child: Text('1:1')),
                                  PopupMenuItem(
                                      value: 'relative',
                                      child: Text(relative
                                          ? 'Trackpad tương đối'
                                          : 'Chạm tuyệt đối')),
                                  CheckedPopupMenuItem(
                                      value: 'overlay',
                                      checked: overlay,
                                      child:
                                          const Text('Bật/tắt lớp trackpad')),
                                  CheckedPopupMenuItem(
                                      value: 'keyboard',
                                      checked: keyboard,
                                      child: const Text('Bật/tắt bàn phím')),
                                  const PopupMenuItem(
                                      value: 'sleep', child: Text('Ngủ')),
                                  const PopupMenuItem(
                                      value: 'restart',
                                      child: Text('Khởi động lại')),
                                  const PopupMenuItem(
                                      value: 'shutdown',
                                      child: Text('Tắt máy')),
                                  const PopupMenuItem(
                                      value: 'settings',
                                      child: Text('Cài đặt')),
                                  const PopupMenuItem(
                                      value: 'disconnect',
                                      child: Text('Ngắt kết nối')),
                                  if (agent.mock)
                                    const PopupMenuItem(
                                        value: 'log',
                                        child: Text('Nhật ký mock')),
                                ],
                              ))),
                      Positioned(
                          bottom: 4,
                          right: 6,
                          child: IgnorePointer(
                              child: Text(
                                  delay == 0
                                      ? 'Ảnh: liên tục'
                                      : 'Đang thử lại ảnh…',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white54)))),
                    ])),
                Expanded(
                    flex: 1,
                    child: SizedBox(
                        key: const ValueKey('keyboard-half'),
                        child: keyboard
                            ? laptopDeck(keyboardPanel())
                            : const SizedBox.expand())),
              ]));
          return imageHeight + 80 > box.maxHeight
              ? SingleChildScrollView(child: content)
              : content;
        }),
      ),
    );
}

class KeyboardSurface extends StatefulWidget {
  const KeyboardSurface(
      {super.key,
      required this.onMove,
      required this.onClick,
      required this.onScroll,
      required this.onDrag,
      this.child,
      this.keyAt,
      this.onPressed});
  final void Function(Offset) onMove;
  final void Function(String) onClick;
  final void Function(double) onScroll;
  final void Function(bool) onDrag;
  final Widget? child;
  final void Function(Offset?)? onPressed;
  final VoidCallback? Function(Offset)? keyAt;
  @override
  State<KeyboardSurface> createState() => _KeyboardSurfaceState();
}

class _KeyboardSurfaceState extends State<KeyboardSurface> {
  final Map<int, Offset> points = {};
  Timer? hold;
  bool moved = false, two = false, dragging = false;
  double distance = 0;
  Offset pending = Offset.zero;
  VoidCallback? pressedKey;
  void finish() {
    hold?.cancel();
    widget.onPressed?.call(null);
    if (dragging) {
      widget.onDrag(false);
    }
    dragging = false;
    points.clear();
  }

  @override
  void dispose() {
    hold?.cancel();
    if (dragging) {
      widget.onDrag(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (points.isEmpty) {
            moved = false;
            two = false;
            distance = 0;
            pending = Offset.zero;
            pressedKey = widget.keyAt?.call(e.position);
            widget.onPressed?.call(e.position);
          }
          points[e.pointer] = e.localPosition;
          if (points.length > 1) {
            two = true;
            widget.onPressed?.call(null);
            hold?.cancel();
            if (dragging) {
              widget.onDrag(false);
              dragging = false;
            }
          } else {
            hold = Timer(const Duration(milliseconds: 500), () {
              if (!moved && points.length == 1) {
                dragging = true;
                widget.onDrag(true);
              }
            });
          }
        },
        onPointerMove: (e) {
          final old = points[e.pointer];
          if (old == null) {
            return;
          }
          final delta = e.localPosition - old;
          points[e.pointer] = e.localPosition;
          distance += delta.distance;
          pending += delta;
          final wasMoved = moved;
          if (distance > 10) {
            moved = true;
            widget.onPressed?.call(null);
            hold?.cancel();
          }
          if (!moved) {
            return;
          }
          if (points.length == 2) {
            widget.onScroll((wasMoved ? delta.dy : pending.dy) / 2);
          } else if (!two) {
            widget.onMove(wasMoved ? delta : pending);
          }
        },
        onPointerUp: (e) {
          widget.onPressed?.call(null);
          points.remove(e.pointer);
          if (points.isEmpty) {
            hold?.cancel();
            if (dragging) {
              widget.onDrag(false);
              dragging = false;
            } else if (!moved) {
              if (two) {
                widget.onClick('right');
              } else if (widget.keyAt != null) {
                pressedKey?.call();
              } else {
                widget.onClick('left');
              }
            }
          }
        },
        onPointerCancel: (_) => finish(),
        child: widget.child ?? const SizedBox.expand(),
      );
}

class RemoteFramePainter extends CustomPainter {
  RemoteFramePainter(this.image, this.source);
  final ui.Image image;
  final Rect source;
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawImageRect(image, source, Offset.zero & size, Paint());
  @override
  bool shouldRepaint(RemoteFramePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.source != source;
}
