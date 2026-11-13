import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'agent.dart';
import 'home_widget_data.dart';
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
  // Step 27: widget background opacity 0 (fully transparent) .. 100.
  int widgetOpacity = widgetOpacityDefault;
  bool ready = false;
  String? error;
  // Step 27: id of the connection whose RemotePage is currently open (set
  // by Home taps and by widget deep links, cleared when the page pops).
  // A widget "connect" tap for the connection that is already open is a
  // no-op — pushing a second RemotePage would try a second RDP session
  // while the first is still running.
  final openConnectionId = ValueNotifier<String?>(null);
  StreamSubscription<Uri?>? _widgetClickedSub;
  // A widget tap that arrives before load() finishes is queued here and
  // handled once the app is ready.
  Uri? _pendingWidgetUri;
  @override
  void initState() {
    super.initState();
    unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    WidgetsBinding.instance.addObserver(this);
    agent = Agent(baseUrl: defaultBaseUrl, mock: mockMode);
    // Step 27: widget taps while the app is already running arrive here.
    try {
      _widgetClickedSub = HomeWidget.widgetClicked.listen(
        (uri) {
          if (!ready) {
            _pendingWidgetUri = uri;
          } else {
            unawaited(_handleWidgetUri(uri));
          }
        },
        onError: (_) {},
      );
    } catch (_) {
      // Widget plugin unavailable (e.g. in tests): the app works without it.
    }
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
      widgetOpacity = prefs!.getInt(widgetOpacityKey)?.clamp(0, 100) ??
          widgetOpacityDefault;
      if (mounted) {
        setState(() => ready = true);
      }
      // Step 27: refresh the widget with the loaded theme/opacity, then
      // handle a widget tap that launched the app cold (if any).
      unawaited(HomeWidgetSync.syncFromPrefs());
      final launchedUri = await _initialWidgetUri();
      if (launchedUri != null) {
        if (mounted && ready) {
          unawaited(_handleWidgetUri(launchedUri));
        } else {
          _pendingWidgetUri = launchedUri;
        }
      }
      final pending = _pendingWidgetUri;
      _pendingWidgetUri = null;
      if (pending != null && mounted && ready) {
        unawaited(_handleWidgetUri(pending));
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
    // Step 27: persist the widget opacity, then push theme + opacity to
    // the widget right away.
    await prefs?.setInt(widgetOpacityKey, clampWidgetOpacity(widgetOpacity));
    if (mounted) {
      setState(() {});
    }
    unawaited(HomeWidgetSync.syncFromPrefs());
  }

  /// Step 27: the deep link the app was cold-started with from the widget,
  /// or null when it was not launched from the widget. Never throws.
  Future<Uri?> _initialWidgetUri() async {
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }

  /// Step 27: runs one parsed widget deep link. Every action ends with a
  /// widget sync so the widget always reflects the new state.
  Future<void> _handleWidgetUri(Uri? uri) async {
    final action = parseHomeWidgetUri(uri);
    if (action == null) return;
    final store = RdpConnectionStore();
    try {
      switch (action.kind) {
        case HomeWidgetActionKind.openApp:
          return;
        case HomeWidgetActionKind.connect:
          final connections = await store.load();
          RdpConnection? target;
          for (final c in connections) {
            if (c.id == action.connectionId) {
              target = c;
              break;
            }
          }
          if (target == null || !mounted) return;
          if (openConnectionId.value == target.id) return;
          await HomeWidgetSync.setCurrentId(target.id);
          unawaited(HomeWidgetSync.syncFromPrefs());
          _openRemote(target);
        case HomeWidgetActionKind.toggleTrackpad:
        case HomeWidgetActionKind.toggleKeyboard:
          final connections = await store.load();
          final current = await _widgetCurrentConnection(connections);
          if (current == null) return;
          final updated = action.kind == HomeWidgetActionKind.toggleTrackpad
              ? current.copyWith(trackpadMode: !current.trackpadMode)
              : current.copyWith(keyboardVisible: !current.keyboardVisible);
          await store.update(updated);
          unawaited(HomeWidgetSync.syncFromPrefs());
          _showWidgetNotice(
              action.kind == HomeWidgetActionKind.toggleTrackpad
                  ? '${updated.trackpadMode ? 'Đã bật' : 'Đã tắt'} Trackpad cho ${updated.name}'
                  : '${updated.keyboardVisible ? 'Đã hiện' : 'Đã ẩn'} bàn phím cho ${updated.name}');
        case HomeWidgetActionKind.nextConnection:
          final connections = await store.load();
          if (connections.length < 2) return;
          final current = await _widgetCurrentConnection(connections);
          final nextId = nextConnectionId(connections, current?.id);
          if (nextId == null) return;
          final next = connections.firstWhere((c) => c.id == nextId);
          await HomeWidgetSync.setCurrentId(next.id);
          unawaited(HomeWidgetSync.syncFromPrefs());
          _showWidgetNotice('Đã chuyển sang ${next.name}');
      }
    } catch (_) {
      // A failed widget action must not crash the app.
    }
  }

  /// Step 27: the connection the widget currently shows (stored current id,
  /// falling back to the favorite / first one, same rule as the widget).
  Future<RdpConnection?> _widgetCurrentConnection(
    List<RdpConnection> connections,
  ) async {
    if (connections.isEmpty) return null;
    final currentId = prefs?.getString(widgetCurrentConnectionKey);
    if (currentId != null && currentId.isNotEmpty) {
      for (final c in connections) {
        if (c.id == currentId) return c;
      }
    }
    return connections.firstWhere(
      (c) => c.favorite,
      orElse: () => connections.first,
    );
  }

  /// Step 27: opens a RemotePage for [connection] from a widget deep link
  /// (same page Home taps open). Tracks the open id so a second tap for
  /// the same connection is a no-op.
  void _openRemote(RdpConnection connection) {
    final nav = navigator.currentState;
    if (nav == null) return;
    openConnectionId.value = connection.id;
    nav.popUntil((route) => route.isFirst);
    unawaited(nav
        .push(MaterialPageRoute(
          builder: (_) => RemotePage(
            agent: agent,
            pollMs: () => pollMs,
            settings: _settingsPage,
            rdpMode: true,
            rdpConnection: connection,
          ),
        ))
        .then((_) {
      if (openConnectionId.value == connection.id) {
        openConnectionId.value = null;
      }
    }));
  }

  /// Step 27: short confirmation after a widget quick-toggle / switch.
  /// Best-effort: silently skipped when no scaffold is on screen yet.
  void _showWidgetNotice(String message) {
    try {
      final context = navigator.currentContext;
      if (context == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {}
  }

  /// Step 27: the Settings page, built from the current app state. Used by
  /// Home and by RemotePage's settings menu so both see the same
  /// widget-opacity value.
  Widget _settingsPage() => SettingsPage(
        theme: theme,
        onThemeChanged: (mode) async {
          theme = mode;
          await save();
        },
        widgetOpacity: widgetOpacity,
        onWidgetOpacityChanged: (value) async {
          widgetOpacity = value;
          await save();
        },
      );

  @override
  void dispose() {
    unawaited(_widgetClickedSub?.cancel());
    openConnectionId.dispose();
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
                    settings: _settingsPage,
                    openConnectionId: openConnectionId,
                  ),
      );
}

class Home extends StatefulWidget {
  const Home(
      {super.key,
      required this.agent,
      required this.pollMs,
      required this.settings,
      this.openConnectionId});
  final Agent agent;
  final int Function() pollMs;
  final Widget Function() settings;
  // Step 27: tracks which connection's RemotePage is open, so a widget
  // "connect" tap for the same connection is a no-op (see _AceAppState).
  // Optional so existing tests keep constructing Home without it.
  final ValueNotifier<String?>? openConnectionId;
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
      // Step 27: the list changed (added/edited/favorited/deleted), so
      // refresh the widget — it shows the same list's current connection.
      unawaited(HomeWidgetSync.syncFromPrefs());
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
    // Step 27: this becomes the widget's current connection, and the
    // open id is tracked so a widget tap for the same connection is a
    // no-op instead of opening a second RDP session.
    widget.openConnectionId?.value = connection.id;
    unawaited(HomeWidgetSync.setCurrentId(connection.id));
    unawaited(HomeWidgetSync.syncFromPrefs());
    unawaited(Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) => RemotePage(
                    agent: widget.agent,
                    pollMs: widget.pollMs,
                    settings: widget.settings,
                    rdpMode: true,
                    rdpConnection: connection)))
        .then((_) {
      if (widget.openConnectionId?.value == connection.id) {
        widget.openConnectionId?.value = null;
      }
    }));
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
      required this.theme,
      required this.onThemeChanged,
      required this.widgetOpacity,
      required this.onWidgetOpacityChanged});
  final ThemeMode theme;
  final Future<void> Function(ThemeMode mode) onThemeChanged;
  // Step 27: widget background opacity 0 (fully transparent) .. 100.
  final int widgetOpacity;
  final Future<void> Function(int opacity) onWidgetOpacityChanged;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ThemeMode mode = widget.theme;
  // Step 27: local slider value (saved only when the drag ends, so the
  // widget is not re-synced on every tick of the drag).
  late int opacity = clampWidgetOpacity(widget.widgetOpacity);
  bool _pinSupported = false;

  @override
  void initState() {
    super.initState();
    _checkPinSupport();
  }

  /// Step 27: Android 8+ lets the app ask the launcher to pin the widget
  /// (system confirmation dialog). Silently hidden when unsupported
  /// (older Android, or no widget plugin — e.g. in tests).
  Future<void> _checkPinSupport() async {
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (mounted) setState(() => _pinSupported = supported ?? false);
    } catch (_) {}
  }

  Future<void> _select(ThemeMode value) async {
    if (value == mode) return;
    setState(() => mode = value);
    await widget.onThemeChanged(value);
  }

  Future<void> _selectOpacity(int value) async {
    final clamped = clampWidgetOpacity(value);
    if (clamped == widget.widgetOpacity) return;
    await widget.onWidgetOpacityChanged(clamped);
  }

  Future<void> _pinWidget() async {
    try {
      await HomeWidget.requestPinWidget(
        qualifiedAndroidName: homeWidgetProviderQualifiedName,
      );
    } catch (_) {
      // The system shows its own dialog/errors; nothing to do here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
        appBar: AppBar(title: const Text('Cài đặt')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Giao diện', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
              clipBehavior: Clip.antiAlias,
              child: RadioGroup<ThemeMode>(
                  groupValue: mode,
                  onChanged: (v) {
                    if (v != null) unawaited(_select(v));
                  },
                  child: const Column(children: [
                    RadioListTile<ThemeMode>(
                        title: Text('Sáng'),
                        subtitle: Text('Giao diện sáng'),
                        secondary: Icon(Icons.light_mode_outlined),
                        value: ThemeMode.light),
                    RadioListTile<ThemeMode>(
                        title: Text('Tối'),
                        subtitle: Text('Giao diện tối'),
                        secondary: Icon(Icons.dark_mode_outlined),
                        value: ThemeMode.dark),
                    RadioListTile<ThemeMode>(
                        title: Text('Theo điện thoại'),
                        subtitle:
                            Text('Theo cài đặt hệ thống của điện thoại'),
                        secondary: Icon(Icons.smartphone_outlined),
                        value: ThemeMode.system),
                  ]))),
          const SizedBox(height: 16),
          // Step 27: home-screen widget (4x2). It follows the theme above
          // (Sáng/Tối/Theo điện thoại); only its background opacity is
          // set here.
          Text('Widget màn hình chính',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Độ trong suốt của widget'),
                              Text('$opacity%',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                            ]),
                        Slider(
                            value: opacity.toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 100,
                            label: '$opacity%',
                            onChanged: (v) =>
                                setState(() => opacity = v.round()),
                            onChangeEnd: (v) =>
                                unawaited(_selectOpacity(v.round()))),
                        Text(
                            '0% là trong suốt hoàn toàn, 100% là đục hoàn toàn. Widget theo chế độ Sáng/Tối ở trên.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: scheme.onSurfaceVariant)),
                        if (_pinSupported) ...[
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                              onPressed: () => unawaited(_pinWidget()),
                              icon: const Icon(Icons.widgets_outlined),
                              label: const Text(
                                  'Thêm widget ra màn hình chính')),
                        ],
                      ]))),
          const SizedBox(height: 16),
          Text(
              'Cài đặt kết nối (địa chỉ, cổng, tài khoản) nằm trong màn hình sửa từng kết nối trên trang chính.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ]));
  }
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
  // Label of the key currently pressed. Mouse keys carry a keyId when two
  // keys share a display label (step 24 had two 'Left' keys); since step 25
  // they are 'Left' and 'Right', so the label alone identifies each one.
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
  // Step 25, item 4: label size for the current keyboard build, computed
  // by keyboardPanel() from the available width (narrow folded screen vs
  // wide unfolded screen) and read by laptopKey(). Only keyboardPanel()
  // calls laptopKey(), and it sets this before any key is built.
  double kbLabelSize = 13;
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
      // Step 25, item 3: in RDP mode the session may have dropped while
      // the app was in the background, and a native state event can be
      // lost if the platform view was disposed in the meantime — either
      // leaves Dart showing a stale "Đang kết nối...". Re-query the native
      // status on resume so the UI matches the real session state; the
      // pane's connectionChanged listener reacts (refills credentials on
      // failure/disconnect, arms the stuck-connect watchdog if still
      // busy), so a stale spinner recovers instead of hanging forever.
      if (widget.rdpMode) unawaited(_resumeRdp());
    }
  }

  /// Re-reads the native RDP status after returning from the background
  /// and adopts it as the Dart state.
  Future<void> _resumeRdp() async {
    if (!mounted) return;
    final status = await rdpController.status();
    if (!mounted || status == null) return;
    rdpController.value = Map<String, dynamic>.from(status);
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
      {double units = 1,
      String? command,
      bool modifier = false,
      String? mouseButton,
      String? keyId}) {
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
        // Mouse buttons (step 24, item 2; step 25, item 1): 'Left' /
        // 'Right' click at the cursor, they are not keys — they must never
        // reach rdpKey, where 'Left'/'Right' mean the VK_LEFT/VK_RIGHT
        // arrow keys (0x125/0x127). Armed modifiers stay armed so
        // Shift+click selection keeps working.
        if (mouseButton != null) {
          if (!rdpController.isConnected) return;
          unawaited(rdpController.clickAtLastPosition(mouseButton));
          return;
        }
        // Caps must reach rdpKey as 'Caps' (a real Caps Lock toggle), even
        // though this widget carries command 'Shift' for agent mode.
        rdpKey(isCaps ? 'Caps' : (command ?? label));
        return;
      }
      // Mouse buttons in agent mode: click at the last cursor position,
      // like the 'Click trái' / 'Click phải' keys below.
      if (mouseButton != null) {
        setState(() => modifiers.clear());
        click(mouseButton);
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
    // Highlight id: defaults to the label; pass a distinct keyId when two
    // keys share a display label so pressing one does not highlight the
    // other.
    keyLabels[target] = keyId ?? label;
    // Step 24, item 3: while Shift is armed (one-shot), the key shows the
    // character Shift will produce (2 -> @, 1 -> !, ...). The key still
    // sends its base label; Windows applies the armed Shift, so the typed
    // character matches the label on screen. Letters already display
    // uppercase, so they do not visibly change. Caps Lock does not arm
    // Shift (step 22), so it never changes the labels.
    final displayLabel =
        modifiers.contains('Shift') ? shiftedLabel(label) : label;
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
                        color: pressedLabel == (keyId ?? label)
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
                                child: Text(displayLabel,
                                    style: TextStyle(
                                        fontSize: kbLabelSize,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white)))))))));
  }

  /// Step 26, item 3: one place for the row-height formula (step 25).
  /// keyboardPanel() uses it with its own box, and the RDP layout uses
  /// it with the page box to size the fixed-height keyboard strip — both
  /// must agree, or the strip would clip or leave a gap. The height is
  /// unchanged from step 25 (step 26, item 2 was cancelled: An kept the
  /// current key height).
  double _keyboardRowHeight(double maxWidth, double maxHeight) {
    final rowCount = widget.rdpMode ? 6 : 7;
    final byWidth = (maxWidth / 16.25 * 1.15).clamp(44.0, 64.0);
    final byHeight =
        maxHeight.isFinite ? (maxHeight - 8) / rowCount : byWidth;
    return min(byWidth, byHeight);
  }

  Widget keyboardPanel() => LayoutBuilder(builder: (context, box) {
        keyTargets.clear();
        keyLabels.clear();
        // Step 25, item 4: the keyboard adapts to the screen instead of
        // stretching with it. Before, every row was Expanded, so on the
        // Fold6's tall narrow folded screen each key was stretched into a
        // tall rectangle and the 13px labels looked lost (and the long
        // PgUp/PgDn/Home/End labels were scaled tiny by FittedBox). Now
        // the row height follows the key WIDTH (16.25 units across the
        // widest rows), clamped so keys are never shorter than a
        // comfortable tap target and never taller than a laptop key.
        // Step 26, item 3: in RDP mode the panel sits in a fixed-height
        // strip pinned to the bottom edge (the parent sizes the strip
        // with _keyboardRowHeight, so this box is exactly
        // rowHeight*rowCount+8 tall and the Column below fills it); in
        // agent mode it is still centered in its Expanded area. The
        // label size follows the row height so single-character labels
        // stay proportionate; FittedBox still shrinks long labels
        // (PgUp/PgDn/Home/End, Backspace, Enter) to fit their key.
        final rowHeight = _keyboardRowHeight(box.maxWidth, box.maxHeight);
        kbLabelSize = (rowHeight * 0.30).clamp(12.0, 16.0);
        // Step 26, item 4: on a narrow (folded) screen the wide keys
        // shrink so the 1-unit letter/number keys get wider (their pixel
        // width is maxWidth / row total). Narrow = folded Fold6 (~378
        // logical px); unfolded is ~700+, so it keeps the step 24/25
        // units. Row totals narrow: F/number 15.5 (F keys still equal
        // the number keys), QWERTY/ASDF/ZXCV rows 15.0, bottom row 15.05
        // (rows 4 and 5 stay equal so ↑ still equals ↓). At 378px a
        // letter key is 378/15.0 = 25.2px wide (was 378/16.25 = 23.3px,
        // +8%); a number key is 378/15.5 = 24.4px (+5%). The row height
        // is untouched (step 26, item 2 was cancelled).
        final narrow = box.maxWidth < 600;
        final delU = narrow ? 2.0 : 2.5;
        final backspaceU = narrow ? 1.5 : 2.0;
        final tabU = narrow ? 1.0 : 1.5;
        final backslashU = narrow ? 1.0 : 1.5;
        final capsU = narrow ? 1.25 : 1.75;
        final enterU = narrow ? 1.75 : 2.25;
        final shiftLU = narrow ? 1.5 : 2.25;
        final shiftRU = narrow ? 1.5 : 2.0;
        final modU = narrow ? 1.15 : 1.25;
        final spaceU = narrow ? 4.0 : 4.5;
        Widget row(int index, List<Widget> keys) => SizedBox(
            height: rowHeight,
            child: Row(key: ValueKey('keyboard-row-$index'), children: keys));
        return Padding(
            padding: const EdgeInsets.all(4),
            child: trackpad(
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Step 25, item 5: the F row is 16 units like the number row
              // below it (was 14), so F1-F12 are exactly as wide as the
              // number keys. The extra width goes to Delete (2.5 units,
              // clearly bigger) and Esc (1.5). Narrow mode keeps the two
              // rows equal (15.5) with Delete at 2.0.
              row(0, [
                laptopKey('Esc', units: 1.5, command: 'Esc'),
                for (var i = 1; i <= 12; i++) laptopKey('F$i', command: 'F$i'),
                laptopKey('Del', units: delU, command: 'Delete'),
              ]),
              row(1, [
                for (final c in '`1234567890-='.split('')) laptopKey(c),
                laptopKey('Backspace', units: backspaceU, command: 'Backspace'),
                laptopKey('PgUp', command: 'PgUp'),
              ]),
              row(2, [
                laptopKey('Tab', units: tabU, command: 'Tab'),
                for (final c in 'QWERTYUIOP[]'.split('')) laptopKey(c),
                laptopKey(r'\', units: backslashU),
                laptopKey('PgDn', command: 'PgDn'),
              ]),
              row(3, [
                laptopKey('Caps',
                    units: capsU, command: 'Shift', modifier: true),
                for (final c in "ASDFGHJKL;'".split('')) laptopKey(c),
                laptopKey('Enter', units: enterU, command: 'Enter'),
                laptopKey('Home', command: 'Home'),
              ]),
              // Step 24, item 4: inverted-T arrows — ↑ sits at the end of
              // this row, above ↓, with End (item 6) at the far right. The
              // right Shift shrinks 2.75 -> 2.0 to make room (row total
              // 16.25, same as the bottom row, so ↑ is exactly the same
              // width as ↓ and the other arrows, and every other key keeps
              // its size). ↑ is a full key, not half-height. Narrow mode:
              // both Shifts 1.5, row total 15.0, same as the bottom row
              // (15.05) so ↑ still equals ↓.
              row(4, [
                laptopKey('Shift',
                    units: shiftLU, command: 'Shift', modifier: true),
                for (final c in 'ZXCVBNM,./'.split('')) laptopKey(c),
                laptopKey('Shift',
                    units: shiftRU, command: 'Shift', modifier: true),
                laptopKey('↑', command: 'Up'),
                laptopKey('End', command: 'End'),
              ]),
              // Step 25, item 1: 'Left' on the left of Space clicks left,
              // 'Right' on the right of Space clicks right. Same size as
              // Alt (1.25), same colors as the other keys. The labels are
              // distinct now, so no keyId is needed for the highlight.
              // Narrow mode: modifiers 1.15, Space 4.0 (row total 15.05).
              row(5, [
                laptopKey('Ctrl', units: modU, modifier: true),
                laptopKey('Win', units: modU, modifier: true),
                laptopKey('Alt', units: modU, modifier: true),
                laptopKey('Left', units: modU, mouseButton: 'left'),
                laptopKey('Space', units: spaceU, command: 'Space'),
                laptopKey('Right', units: modU, mouseButton: 'right'),
                laptopKey('Alt', units: modU, modifier: true),
                laptopKey('Ctrl', units: modU, modifier: true),
                for (final e in const {
                  '←': 'Left',
                  '↓': 'Down',
                  '→': 'Right'
                }.entries)
                  laptopKey(e.key, command: e.value),
              ]),
              if (!widget.rdpMode)
                row(6, [laptopKey('Click trái'), laptopKey('Click phải')]),
            ]))));
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
                      theme: ThemeMode.system,
                      onThemeChanged: (_) async {},
                      widgetOpacity: widgetOpacityDefault,
                      onWidgetOpacityChanged: (_) async {})));
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
            // Step 26, item 3: the keyboard is a fixed-height strip
            // pinned to the bottom edge — NOT half the screen any more.
            // The remote screen (Expanded) takes all the remaining space
            // above it, down to the top edge of the keys, like the
            // unfolded layout. The strip height comes from the same
            // _keyboardRowHeight formula keyboardPanel() uses, so the
            // strip is exactly 6 rows + padding tall (no clip, no gap
            // below the keys). The RDP resolution follows the new
            // SurfaceView size through the existing DISP path
            // (surfaceChanged -> scheduleResize); if DISP fails the
            // session keeps running and the picture letterboxes.
            // Hiding the keyboard still lets the remote fill the whole
            // page. Switching never drops the RDP session and never
            // resets the cursor.
            return ValueListenableBuilder<bool>(
              valueListenable: rdpController.keyboardVisible,
              builder: (context, kbVisible, _) {
                final kbHeight = kbVisible
                    ? _keyboardRowHeight(box.maxWidth, box.maxHeight) * 6 + 8
                    : 0.0;
                return Column(children: [
                  Expanded(
                      child: SizedBox(
                          key: const ValueKey('remote-half'),
                          child: RdpConnectionPane(
                              controller: rdpController,
                              initialConnection: widget.rdpConnection))),
                  if (kbVisible)
                    SizedBox(
                        key: const ValueKey('keyboard-half'),
                        height: kbHeight,
                        child:
                            laptopDeck(keyboardSwipe(keyboardPanel()))),
                ]);
              },
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
