import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'agent.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AceApp());
}

const mockMode = bool.fromEnvironment('ACE_MOCK');

class AceApp extends StatefulWidget {
  const AceApp({super.key, this.now = DateTime.now});
  final DateTime Function() now;
  @override
  State<AceApp> createState() => _AceAppState();
}

class _AceAppState extends State<AceApp> with WidgetsBindingObserver {
  final storage = const FlutterSecureStorage();
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
                biometricHint: 'Xác minh vân tay',
                biometricNotRecognized: 'Chưa nhận diện. Thử lại.',
                biometricRequiredTitle: 'Cần đăng ký vân tay',
                biometricSuccess: 'Đã xác minh',
                cancelButton: 'Hủy',
                signInTitle: 'Mở khóa phiên',
                goToSettingsButton: 'Mở cài đặt',
                goToSettingsDescription:
                    'Đăng ký vân tay trong cài đặt điện thoại.',
                deviceCredentialsRequiredTitle: 'Cần khóa điện thoại',
                deviceCredentialsSetupDescription:
                    'Thiết lập khóa trong cài đặt điện thoại.',
              )
            ],
            options: const AuthenticationOptions(biometricOnly: true));
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
        setState(() => error = e is PlatformException
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
                                            pollMs: widget.pollMs)))
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
            value: mode,
            decoration: const InputDecoration(labelText: 'Giao diện'),
            items: const [
              DropdownMenuItem(
                  value: ThemeMode.system, child: Text('Theo điện thoại')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Sáng')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Tối'))
            ],
            onChanged: (v) => setState(() => mode = v!)),
        DropdownButtonFormField<int>(
            value: ms,
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
  const RemotePage({super.key, required this.agent, required this.pollMs});
  final Agent agent;
  final int Function() pollMs;
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
  Agent get agent => widget.agent;
  ui.Image? frame;
  double fitScale = 1;
  String? failedPath;
  Map<String, dynamic>? failedData;
  Size imageSize = const Size(1, 1);
  final transform = TransformationController();
  final text = TextEditingController();
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
    if (!mounted || !running || polling) {
      return;
    }
    polling = true;
    final watch = Stopwatch()..start();
    try {
      final bytes = await agent.screenshot(monitor);
      final codec = await ui.instantiateImageCodec(bytes);
      final decoded = await codec.getNextFrame();
      final size =
          Size(decoded.image.width.toDouble(), decoded.image.height.toDouble());
      codec.dispose();
      if (mounted) {
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
      delay = max(
          widget.pollMs(),
          min(
              8000,
              max(watch.elapsedMilliseconds,
                  widget.pollMs() * (1 << min(failures, 4)))));
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
          'monitor': targetMonitor,
        });
      } catch (e) {
        if (mounted) {
          setState(() {
            error = 'Lệnh điều khiển bị gián đoạn. ${clean(e)}';
            failedPath = path;
            failedData = {...data, 'monitor': targetMonitor};
            controlsHealthy = false;
          });
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
              'Hãy lưu công việc trên PC. Nếu agent chưa có /power, app sẽ mở Win+R, gõ lệnh shutdown rồi Enter (phụ thuộc focus Windows). Tiếp tục $label?')) {
        return;
      }
    } else if (!await confirm(
        label, 'Máy ngủ sẽ không gọi dậy được từ app v1. Tiếp tục?')) {
      return;
    }
    if (agent.capabilities.contains('power')) {
      await send('/power', {'action': action});
    } else if (action == 'sleep') {
      await send('/key', {'key': 'Sleep'});
    } else {
      // Legacy fallback: use Windows Run. Success of HTTP is not OS execution proof.
      await send('/key', {'key': 'Win+R'});
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || !running || !controlsHealthy) {
        return;
      }
      await typeText(
          action == 'shutdown' ? 'shutdown /s /t 0' : 'shutdown /r /t 0');
      await send('/key', {'key': 'Enter'});
    }
    if (controlsHealthy) {
      notice('Đã gửi yêu cầu $label. Chưa xác minh Windows đã thực thi.');
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
    text.dispose();
    super.dispose();
  }

  Widget screenshot() => LayoutBuilder(builder: (context, box) {
        if (frame == null) {
          return const Center(child: Text('Đang lấy ảnh…'));
        }
        final d = display;
        final source =
            d?.cropRect(agent.virtualOrigin, agent.virtualSize, imageSize) ??
                (Offset.zero & imageSize);
        final scale = box.maxWidth / source.width;
        fitScale = scale;
        final fitted = Size(box.maxWidth, source.height * scale);
        return ClipRect(
            child: OverflowBox(
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

  Widget trackpad({bool translucent = false, Widget? child}) => KeyboardSurface(
        child: child,
        keyAt: child == null ? null : keyAt,
        onMove: move,
        onClick: click,
        onScroll: (dy) => send('/scroll', {'delta': (-dy * 3).round()}),
        onDrag: (down) {
          if (!agent.capabilities.contains('mouse_drag')) {
            if (down) {
              notice('Agent không có mouse_drag (down/up).');
            }
            return;
          }
          dragging = down;
          send('/click', {'button': 'left', 'action': down ? 'down' : 'up'});
        },
      );
  Widget shortcuts() => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final entry in const {
          'Sao chép': 'Ctrl+C',
          'Dán trên PC': 'Ctrl+V',
          'Đổi cửa sổ': 'Alt+Tab',
          'Hiện màn hình nền': 'Win+D',
          'Khóa máy': 'Win+L',
          'Ctrl+Alt+Del': 'Ctrl+Alt+Del',
          'Chụp màn hình': 'PrintScreen',
          'Quản lý tác vụ': 'Ctrl+Shift+Esc'
        }.entries)
          Padding(
              padding: const EdgeInsets.all(2),
              child: OutlinedButton(
                  onPressed: () {
                    if (entry.value == 'Ctrl+Alt+Del' &&
                        !agent.capabilities.contains('sas')) {
                      notice(
                          'Ctrl+Alt+Del cần agent hỗ trợ SAS của Windows; SendKeys thông thường không thực hiện được.');
                    } else {
                      send('/key', {'key': entry.value});
                    }
                  },
                  child: Text(entry.key))),
      ]));
  final keyTargets = <GlobalKey, VoidCallback>{};

  VoidCallback? keyAt(Offset position) {
    for (final entry in keyTargets.entries) {
      final box = entry.key.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).contains(position)) {
        return entry.value;
      }
    }
    return null;
  }

  Widget laptopKey(String label,
      {double units = 1, String? command, bool modifier = false}) {
    final selected = modifier && modifiers.contains(command ?? label);
    void press() {
      if (label == 'Click Phải') {
        click('right');
      } else if (modifier) {
        setState(() {
          selected ? modifiers.remove(command ?? label) : modifiers.add(command ?? label);
        });
      } else if (command != null) {
        key(command);
      } else if (modifiers.isEmpty) {
        typeText(label);
      } else {
        key(label.toUpperCase());
      }
    }
    final target = GlobalKey();
    keyTargets[target] = press;
    return Expanded(
      flex: (units * 100).round(),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Semantics(
          button: true, selected: selected, label: label, onTap: press,
          child: Container(
            key: target,
            decoration: BoxDecoration(
              color: selected ? const Color(0xff505762) : const Color(0xff292b30),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xff3c3e43))),
            child: Center(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(fit: BoxFit.scaleDown,
                child: label == 'Win'
                  ? IgnorePointer(child: FilterChip(
                      label: const Text('Win'), selected: selected,
                      onSelected: (_) => press()))
                  : Text(label, style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: Colors.white)))))))));
  }

  Widget keyboardPanel() => LayoutBuilder(builder: (context, box) {
        // Scroll only on short windows; keep every key available without overflow.
        keyTargets.clear();
        final height = max(216.0, box.maxHeight);
        return SingleChildScrollView(
            child: SizedBox(
                height: height,
                child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(children: [
                      SizedBox(
                          height: 44,
                          child: Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: text,
                                    maxLines: 1,
                                    decoration: const InputDecoration(
                                        hintText: 'Nhập tiếng Việt có dấu',
                                        isDense: true),
                                    onSubmitted: (v) async {
                                      await typeText(v);
                                      if (controlsHealthy) text.clear();
                                    })),
                            IconButton(
                                tooltip: 'Gõ',
                                icon: const Icon(Icons.send),
                                onPressed: () async {
                                  await typeText(text.text);
                                  if (controlsHealthy) text.clear();
                                }),
                            TextButton(
                                onPressed: () async {
                                  try {
                                    final data = await Clipboard.getData(
                                        Clipboard.kTextPlain);
                                    await typeText(data?.text ?? '');
                                  } catch (_) {
                                    notice(
                                        'Không đọc được clipboard điện thoại.');
                                  }
                                },
                                child: const Text('Dán'))
                          ])),
                      Expanded(child: trackpad(child: Column(children: [
                        Expanded(child: Row(children: [
                          laptopKey('esc', command: 'Esc'),
                          laptopKey('tab', units: 1.5, command: 'Tab'),
                          laptopKey('Ctrl', command: 'Ctrl', modifier: true),
                          laptopKey('Alt', command: 'Alt', modifier: true),
                          laptopKey('Win', modifier: true),
                          laptopKey('⇧', command: 'Shift', modifier: true),
                          for (final e in const {'←':'Left','↑':'Up','↓':'Down','→':'Right'}.entries)
                            laptopKey(e.key, command: e.value),
                          laptopKey('Click Phải', units: 2.5),
                        ])),
                        Expanded(child: Row(children: [
                          for (final c in 'qwertyuiop'.split('')) laptopKey(c),
                          laptopKey('⌫', units: 2, command: 'Backspace'),
                        ])),
                        Expanded(child: Row(children: [
                          const Spacer(flex: 50),
                          for (final c in 'asdfghjkl'.split('')) laptopKey(c),
                          laptopKey('⏎', units: 2.25, command: 'Enter'),
                          const Spacer(flex: 25),
                        ])),
                        Expanded(child: Row(children: [
                          const Spacer(flex: 75),
                          for (final c in 'zxcvbnm,.'.split('')) laptopKey(c),
                          laptopKey('⇧', units: 2.25, command: 'Shift', modifier: true),
                        ])),
                        Expanded(child: Row(children: [
                          laptopKey('Ctrl', units: 1.25, command: 'Ctrl', modifier: true),
                          laptopKey('Alt', units: 1.25, command: 'Alt', modifier: true),
                          laptopKey('Space', units: 5.5, command: 'Space'),
                          for (final e in const {'←':'Left','↑':'Up','↓':'Down','→':'Right'}.entries)
                            laptopKey(e.key, command: e.value),
                        ])),
                      ]))),
                    ]))));
      });

  Widget laptopDeck(Widget child) {
    return Theme(data: ThemeData.dark(useMaterial3: true),
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
  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
        appBar: AppBar(title: Text('ace • Màn hình $monitor'), actions: [
          if (agent.mock)
            IconButton(
                tooltip: 'Nhật ký mock',
                onPressed: showLog,
                icon: const Icon(Icons.receipt_long)),
          IconButton(
              tooltip: 'Bàn phím',
              onPressed: () => setState(() => keyboard = !keyboard),
              icon: const Icon(Icons.keyboard)),
          PopupMenuButton<String>(
              tooltip: 'Thao tác nhanh',
              onSelected: power,
              itemBuilder: (_) => const [
                    PopupMenuItem(value: 'sleep', child: Text('Ngủ')),
                    PopupMenuItem(
                        value: 'restart', child: Text('Khởi động lại')),
                    PopupMenuItem(value: 'shutdown', child: Text('Tắt máy'))
                  ]),
        ]),
        body: SafeArea(
            child: Column(children: [
          if (error != null || !controlsHealthy)
            Container(
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(6),
                child: Row(children: [
                  Expanded(
                      child: Text(error ?? 'Lệnh điều khiển bị gián đoạn.')),
                  TextButton(
                      onPressed: () async {
                        final path = failedPath;
                        final data = failedData;
                        if (path == null || data == null) return;
                        setState(() {
                          error = null;
                          controlsHealthy = true;
                        });
                        await send(path, data);
                      },
                      child: const Text('Thử lại'))
                ])),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final d in agent.displays)
                  TextButton(
                      style: TextButton.styleFrom(
                          backgroundColor: d.id == monitor
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null),
                      onPressed: () => setState(() {
                            monitor = d.id;
                            transform.value = Matrix4.identity();
                            cursor =
                                Offset(d.x + d.width / 2, d.y + d.height / 2);
                          }),
                      child: Text(
                          'Màn hình ${d.id}${d.id == monitor ? ' ✓' : ''}')),
                TextButton(
                    onPressed: () => transform.value = Matrix4.identity(),
                    child: const Text('Vừa màn hình')),
                TextButton(
                    onPressed: () => transform.value =
                        Matrix4.diagonal3Values(1 / fitScale, 1 / fitScale, 1),
                    child: const Text('1:1')),
                Switch(
                    value: relative,
                    onChanged: (v) => setState(() => relative = v)),
                Text(relative ? 'Trackpad tương đối' : 'Chạm tuyệt đối'),
                if (!landscape)
                  IconButton(
                      tooltip: 'Bật/tắt lớp trackpad',
                      onPressed: () => setState(() {
                            overlay = !overlay;
                            if (overlay) {
                              relative = true;
                            }
                          }),
                      icon: Icon(
                          overlay ? Icons.touch_app : Icons.pan_tool_outlined)),
                Text('Ảnh: ${(1000 / delay).toStringAsFixed(1)}/giây'),
              ])),
          Expanded(child: Column(children: [
            if (landscape)
              Expanded(child: screenshot())
            else
              AspectRatio(
                aspectRatio: display == null ? 16 / 9 : display!.width / display!.height,
                child: screenshot()),
            if (keyboard) Expanded(child: laptopDeck(keyboardPanel())),
          ])),
          shortcuts(),
        ])));
  }


}

class KeyboardSurface extends StatefulWidget {
  const KeyboardSurface(
      {super.key,
      required this.onMove,
      required this.onClick,
      required this.onScroll,
      required this.onDrag,
      this.child, this.keyAt});
  final void Function(Offset) onMove;
  final void Function(String) onClick;
  final void Function(double) onScroll;
  final void Function(bool) onDrag;
  final Widget? child;
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
          }
          points[e.pointer] = e.localPosition;
          if (points.length > 1) {
            two = true;
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
