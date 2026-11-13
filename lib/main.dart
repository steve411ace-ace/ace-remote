import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'rdp_credentials.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'agent.dart';
import 'rdp_input.dart';
import 'rdp_surface.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AceApp());
}

const mockMode = bool.fromEnvironment('ACE_MOCK');
const rdpPrototype = bool.fromEnvironment('ACE_RDP');

class AceApp extends StatefulWidget {
  const AceApp({super.key, this.now = DateTime.now});
  final DateTime Function() now;
  @override
  State<AceApp> createState() => _AceAppState();
}

class _AceAppState extends State<AceApp> with WidgetsBindingObserver {
  final auth = LocalAuthentication();
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  final navigator = GlobalKey<NavigatorState>();
  SharedPreferences? prefs;
  late final Agent agent;
  ThemeMode theme = ThemeMode.system;
  int pollMs = 500;
  bool ready = false, unlocked = false, hasPin = false, busy = false;
  String? error;
  late DateTime lastActivity;
  bool securityReady = false;
  bool biometricAvailable = false;
  Timer? idle;
  int failed = 0;
  DateTime? retryAt;
  @override
  void initState() {
    super.initState();
    unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    lastActivity = widget.now();
    WidgetsBinding.instance.addObserver(this);
    agent = Agent(baseUrl: defaultBaseUrl, mock: mockMode);
    load();
    idle = Timer.periodic(const Duration(seconds: 1), (_) {
      if (unlocked &&
          widget.now().difference(lastActivity) >= const Duration(minutes: 5)) {
        lock();
      }
    });
  }

  Future<void> load() async {
    try {
      prefs = await SharedPreferences.getInstance();
      agent.baseUrl =
          prefs!.getString('ace_remote_v1_base_url') ?? defaultBaseUrl;
      pollMs = prefs!.getInt('ace_remote_v1_poll_ms') == 1000 ? 1000 : 500;
      theme = ThemeMode
          .values[prefs!.getInt('ace_remote_v1_theme')?.clamp(0, 2) ?? 0];
      hasPin = await storage.read(key: 'ace_pin_hash') != null;
      try {
        biometricAvailable =
            await auth.canCheckBiometrics.timeout(const Duration(seconds: 2)) &&
                (await auth
                        .getAvailableBiometrics()
                        .timeout(const Duration(seconds: 2)))
                    .isNotEmpty;
      } catch (_) {
        biometricAvailable = false;
      }
      if (mounted) {
        setState(() {
          ready = true;
          securityReady = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          ready = true;
          error =
              'Không mở được kho bảo mật. Khởi động lại ứng dụng để thử lại.';
        });
      }
    }
  }

  void lock() {
    if (!mounted) {
      return;
    }
    navigator.currentState?.popUntil((r) => r.isFirst);
    pin.clear();
    confirmPin.clear();
    setState(() => unlocked = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    }
    if (state == AppLifecycleState.resumed &&
        widget.now().difference(lastActivity) >= const Duration(minutes: 5)) {
      lock();
    }
  }

  String digest(String salt, String value) {
    // Iterated salted digest; secret material is additionally in Android Keystore storage.
    List<int> bytes = utf8.encode('$salt:$value');
    for (var i = 0; i < 60000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }

  Future<void> unlock({bool biometric = false}) async {
    if (!securityReady ||
        busy ||
        (retryAt != null && widget.now().isBefore(retryAt!))) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      var ok = false;
      if (biometric && hasPin) {
        ok = await auth.authenticate(
            localizedReason: 'Mở khóa Ace Remote',
            authMessages: const [
              AndroidAuthMessages(
                signInHint: 'Xác minh vân tay',
                cancelButton: 'Hủy',
                signInTitle: 'Mở khóa phiên',
              )
            ],
            biometricOnly: true);
      } else {
        if (!RegExp(r'^\d{4,6}$').hasMatch(pin.text)) {
          throw Exception('PIN phải gồm 4–6 chữ số.');
        }
        if (!hasPin) {
          if (pin.text != confirmPin.text) {
            throw Exception('Hai mã PIN chưa khớp.');
          }
          final salt = base64Encode(
              List.generate(32, (_) => Random.secure().nextInt(256)));
          await storage.write(key: 'ace_pin_salt', value: salt);
          await storage.write(
              key: 'ace_pin_hash', value: digest(salt, pin.text));
          hasPin = true;
          ok = true;
        } else {
          final salt = await storage.read(key: 'ace_pin_salt');
          final expected = await storage.read(key: 'ace_pin_hash');
          ok = salt != null && digest(salt, pin.text) == expected;
        }
      }
      if (!ok) {
        failed++;
        if (failed >= 5) {
          retryAt = widget.now().add(const Duration(seconds: 30));
        }
        throw Exception(failed >= 5
            ? 'Thử lại sau 30 giây.'
            : 'Chưa mở khóa. Kiểm tra PIN hoặc vân tay.');
      }
      failed = 0;
      retryAt = null;
      pin.clear();
      confirmPin.clear();
      lastActivity = widget.now();
      if (mounted) {
        setState(() => unlocked = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is PlatformException || e is LocalAuthException
            ? 'Vân tay chưa sẵn sàng. Hãy dùng PIN.'
            : e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
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
    idle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    agent.dispose();
    pin.dispose();
    confirmPin.dispose();
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
        builder: (context, child) => Listener(
            onPointerDown: (_) => lastActivity = widget.now(),
            onPointerMove: (_) => lastActivity = widget.now(),
            child: child),
        home: !ready
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : !unlocked
                ? Scaffold(
                    appBar: AppBar(title: const Text('Ace Remote')),
                    body: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(24),
                                children: [
                                  Text(
                                      hasPin
                                          ? 'Mở khóa phiên'
                                          : 'Đặt PIN lần đầu',
                                      style: const TextStyle(fontSize: 24)),
                                  TextField(
                                      controller: pin,
                                      obscureText: true,
                                      maxLength: 6,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      decoration: const InputDecoration(
                                          labelText: 'PIN (4–6 số)')),
                                  if (!hasPin)
                                    TextField(
                                        controller: confirmPin,
                                        obscureText: true,
                                        maxLength: 6,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly
                                        ],
                                        decoration: const InputDecoration(
                                            labelText: 'Nhập lại PIN')),
                                  if (error != null)
                                    Text(error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                  FilledButton(
                                      onPressed: busy || !securityReady
                                          ? null
                                          : () => unlock(),
                                      child: Text(busy
                                          ? 'Đang kiểm tra…'
                                          : hasPin
                                              ? 'Mở khóa'
                                              : 'Lưu PIN')),
                                  if (hasPin && biometricAvailable)
                                    OutlinedButton(
                                        onPressed: busy
                                            ? null
                                            : () => unlock(biometric: true),
                                        child: const Text('Dùng vân tay')),
                                ]))),
                  )
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
                        }),
                    onLock: lock),
      );
}

class Home extends StatefulWidget {
  const Home(
      {super.key,
      required this.agent,
      required this.pollMs,
      required this.settings,
      required this.onLock});
  final Agent agent;
  final int Function() pollMs;
  final Widget Function() settings;
  final VoidCallback onLock;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String status = 'Đang kiểm tra…';
  bool online = false, checking = false;
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    if (checking) {
      return;
    }
    setState(() => checking = true);
    try {
      await widget.agent.health();
      if (mounted) {
        setState(() {
          online = true;
          status = 'Trực tuyến';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          online = false;
          status = 'Ngoại tuyến • ${clean(e)}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Ace Remote'), actions: [
        IconButton(
            tooltip: 'Cài đặt',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute<void>(builder: (_) => widget.settings()));
              check();
            }),
        IconButton(
            tooltip: 'Khóa phiên',
            onPressed: widget.onLock,
            icon: const Icon(Icons.lock))
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.agent.mock)
          const Text('CHẾ ĐỘ MÔ PHỎNG • Không gửi lệnh tới PC'),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ace — Windows',
                          style: TextStyle(fontSize: 24)),
                      Text(widget.agent.baseUrl),
                      Text(status),
                      Wrap(spacing: 12, children: [
                        FilledButton(
                            onPressed: online && !checking
                                ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                        builder: (_) => RemotePage(
                                            agent: widget.agent,
                                            pollMs: widget.pollMs,
                                            settings: widget.settings)))
                                : null,
                            child: const Text('Kết nối')),
                        OutlinedButton(
                            onPressed: checking ? null : check,
                            child: const Text('Thử lại'))
                      ])
                    ]))),
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
      this.rdpMode = rdpPrototype});
  final Widget Function()? settings;
  final bool rdpMode;
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
    if (key == 'Caps') key = 'Shift';
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
    final selected = modifier && modifiers.contains(command ?? label);
    void press() {
      if (widget.rdpMode) {
        rdpKey(command ?? label);
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
                        color: pressedLabel == label
                            ? const Color(0xff8b929e)
                            : selected
                                ? const Color(0xff505762)
                                : const Color(0xff292b30),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xff3c3e43))),
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
  Widget build(BuildContext context) => Scaffold(
        body: LayoutBuilder(builder: (context, box) {
          if (widget.rdpMode) {
            return Column(children: [
              Expanded(
                  child: SizedBox(
                      key: const ValueKey('remote-half'),
                      child: RdpConnectionPane(controller: rdpController))),
              Expanded(
                  child: SizedBox(
                      key: const ValueKey('keyboard-half'),
                      child: laptopDeck(keyboardPanel()))),
            ]);
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
