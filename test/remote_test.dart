import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:ace_remote/agent.dart';
import 'package:ace_remote/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

int stateMonitor(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(RemotePage));
  return state.monitor as int;
}

void main() {
  testWidgets('Home shows only the supported Windows PC', (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    expect(find.text('Mac\u0042ook'), findsNothing);
    expect(find.textContaining('Chưa h\u1ed7 trợ'), findsNothing);
    expect(find.byType(Card), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AceApp opens straight to Home without a PIN gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AceApp());
    await tester.pumpAndSettle();
    expect(find.text('Đặt PIN lần đầu'), findsNothing);
    expect(find.text('Mở khóa phiên'), findsNothing);
    expect(find.text('ace — Windows'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Live polling recovers after a failed frame and resets backoff',
      (tester) async {
    final png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(4, 2);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      return bytes;
    }))!;
    var requests = 0;
    final nextFrame = Completer<http.Response>();
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          requests++;
          if (requests == 1) return http.Response('frame unavailable', 503);
          if (requests == 2) return http.Response.bytes(png, 200);
          return nextFrame.future;
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: agent, pollMs: () => 1000)));
    await tester.pump();
    final dynamic state = tester.state(find.byType(RemotePage));
    expect(state.failures, 1);
    expect(state.error, isNull);
    expect(state.delay, 2000);
    await tester.pump(const Duration(milliseconds: 2000));
    // The successful frame schedules the next poll with a zero-delay timer.
    // Frame decoding needs real time, which varies under load, so wait
    // until the next request starts instead of assuming one decode window.
    for (var i = 0; i < 10 && requests < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(requests, 3);
    expect(state.failures, 0);
    expect(state.delay, 0);
    expect(state.error, isNull);
    expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<RemoteFramePainter>(),
        isNotEmpty);
    expect(find.text('Ảnh: liên tục'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(requests, 3);
    await tester.pumpWidget(const SizedBox());
    nextFrame.complete(http.Response('frame unavailable', 503));
    await tester.pump();
  });

  testWidgets('Monitor aspect changes height; full trackpad sweeps reach edges',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final moves = <Map<String, dynamic>>[];
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('no frame', 503);
          moves.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 200);
        }));
    agent.displays = [
      const DisplayInfo(1, 0, 0, 1920, 1080),
      const DisplayInfo(2, 0, 0, 1200, 1200),
    ];
    addTearDown(agent.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: agent, pollMs: () => 1000)));
    final remote = find.byKey(const ValueKey('remote-half'));
    expect(tester.getSize(remote), const Size(800, 450));
    final dynamic state = tester.state(find.byType(RemotePage));
    final pad = find.byType(KeyboardSurface);
    final bounds = tester.getRect(pad);
    state.cursor = Offset.zero;
    final horizontal =
        await tester.startGesture(bounds.topLeft + const Offset(0.1, 20));
    await horizontal.moveTo(Offset(bounds.right - 0.1, bounds.top + 20));
    await horizontal.up();
    await tester.pump();
    expect(moves.last['x'], 1919);
    expect(moves.last['y'], 0);
    state.cursor = Offset.zero;
    final vertical =
        await tester.startGesture(bounds.topLeft + const Offset(20, 0.1));
    await vertical.moveTo(Offset(bounds.left + 20, bounds.bottom - 0.1));
    await vertical.up();
    await tester.pump();
    expect(moves.last['x'], 0);
    expect(moves.last['y'], 1079);
    await tester.tap(find.byTooltip('Điều khiển'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Màn hình 2'));
    await tester.pumpAndSettle();
    expect(tester.getSize(remote), const Size(800, 800));
    expect(tester.getSize(find.byKey(const ValueKey('keyboard-half'))),
        const Size(800, 600));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('KeyboardSurface: right click, movement, scroll, drag down/up',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: KeyboardSurface(
      onMove: (_) => events.add('move'),
      onClick: (b) => events.add(b),
      onScroll: (_) => events.add('scroll'),
      onDrag: (v) => events.add('drag:$v'),
    ))));
    final p = tester.getCenter(find.byType(KeyboardSurface));
    final a = await tester.startGesture(p, pointer: 1);
    final b = await tester.startGesture(p + const Offset(20, 0), pointer: 2);
    await b.up();
    await a.up();
    expect(events, ['right']);
    events.clear();
    final c = await tester.startGesture(p);
    await c.moveBy(const Offset(20, 10));
    await c.up();
    expect(events, ['move']);
    events.clear();
    final d = await tester.startGesture(p, pointer: 3);
    final e = await tester.startGesture(p + const Offset(20, 0), pointer: 4);
    await e.moveBy(const Offset(0, 20));
    await e.up();
    await d.up();
    expect(events, ['scroll']);
    events.clear();
    final f = await tester.startGesture(p);
    await tester.pump(const Duration(milliseconds: 510));
    await f.moveBy(const Offset(20, 0));
    await f.up();
    expect(events, ['drag:true', 'move', 'drag:false']);
  });
  testWidgets(
      'Keyboard tap versus move and two-finger scroll send distinct commands',
      (tester) async {
    final requests = <http.Request>[];
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('no frame', 503);
          requests.add(request);
          return http.Response('{}', 200);
        }));
    agent.displays = [const DisplayInfo(1, 0, 0, 1920, 1080)];
    addTearDown(agent.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: agent, pollMs: () => 1000)));
    final q = tester.getCenter(find.text('Q'));
    final tap = await tester.startGesture(q);
    await tap.moveBy(const Offset(4, 2));
    await tap.up();
    await tester.pump();
    expect(requests.map((r) => r.url.path), ['/type']);
    expect(jsonDecode(requests.single.body)['text'], 'q');
    requests.clear();

    final drag = await tester.startGesture(q);
    await drag.moveBy(const Offset(4, 2));
    await drag.moveBy(const Offset(16, 8));
    await drag.up();
    await tester.pump();
    expect(requests.map((r) => r.url.path), ['/move']);
    final move = jsonDecode(requests.single.body);
    final pad = tester.getSize(find.byType(KeyboardSurface));
    expect(move['x'], (20 * 1920 / pad.width).round());
    expect(move['y'], (10 * 1080 / pad.height).round());
    expect(move.containsKey('relative'), isFalse);
    requests.clear();

    final first = await tester.startGesture(q, pointer: 11);
    final second =
        await tester.startGesture(q + const Offset(30, 0), pointer: 12);
    await second.moveBy(const Offset(0, 20));
    await second.up();
    await first.up();
    await tester.pump();
    expect(requests.map((r) => r.url.path), ['/scroll']);
    expect(jsonDecode(requests.single.body)['delta'], -30);
    requests.clear();

    final one = await tester.startGesture(q, pointer: 13);
    final two = await tester.startGesture(q + const Offset(30, 0), pointer: 14);
    await two.up();
    await one.up();
    await tester.pump();
    expect(requests.map((r) => r.url.path), ['/click']);
    expect(jsonDecode(requests.single.body)['button'], 'right');
    requests.clear();

    expect(find.byType(TextField), findsNothing);
    expect(requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Pending screenshot allows input; retry keeps original monitor',
      (tester) async {
    final screenshot = Completer<http.Response>();
    final screenshotRequests = <http.Request>[];
    final commands = <Map<String, dynamic>>[];
    final a = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            screenshotRequests.add(request);
            return screenshot.future;
          }
          commands.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', commands.length <= 2 ? 503 : 200);
        }));
    a.displays = [
      const DisplayInfo(1, 0, 0, 1920, 1080),
      const DisplayInfo(2, -1920, 0, 1536, 864),
    ];
    addTearDown(a.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    await tester.tap(find.text('Click phải'));
    await tester.pump();
    await tester.pump();
    expect(screenshot.isCompleted, isFalse);
    expect(screenshotRequests, hasLength(1));
    expect(screenshotRequests.single.url.path, '/screenshot');
    expect(screenshotRequests.single.url.queryParameters,
        {'monitor': '0', 'format': 'jpeg', 'quality': '70', 'scale': '0.5'});
    expect(commands, hasLength(2));
    expect(find.textContaining('Lệnh điều khiển bị gián đoạn'), findsOneWidget);
    await tester.tap(find.byTooltip('Điều khiển'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Màn hình 2'));
    await tester.pumpAndSettle();
    expect(stateMonitor(tester), 2);
    await tester.tap(find.text('Thử lại'));
    // Tapping the SnackBar action starts its dismiss animation; settle so the
    // snackbar leaves the tree before asserting the error text is gone.
    await tester.pumpAndSettle();
    expect(commands, hasLength(3));
    expect(commands.last['monitor'], 1);
    expect(find.textContaining('Lệnh điều khiển bị gián đoạn'), findsNothing);
    // A failed frame leaves the selected tab and input controls available.
    screenshot.complete(http.Response('frame unavailable', 503));
    await tester.pump();
    await tester.pump();
    expect(stateMonitor(tester), 2);
    expect(find.textContaining('Lệnh điều khiển bị gián đoạn'), findsNothing);
    await tester.tap(find.text('Click phải'));
    await tester.pump();
    expect(commands.last['monitor'], 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Width fit preserves the entire per-monitor frame and touch mapping',
      (tester) async {
    final png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(192, 108);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      return png;
    }))!;
    final screenshotUrls = <Uri>[];
    final moves = <Map<String, dynamic>>[];
    final moveRequests = <http.Request>[];
    final a = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response(
                jsonEncode({
                  'ok': true,
                  'width': 1920,
                  'height': 1080,
                  'cursorX': 100,
                  'cursorY': 200,
                  'screens': [
                    {
                      'primary': false,
                      'x': -1920,
                      'y': 0,
                      'width': 1536,
                      'height': 864
                    },
                    {
                      'primary': true,
                      'x': 0,
                      'y': 0,
                      'width': 1920,
                      'height': 1080
                    },
                  ],
                }),
                200);
          }
          if (request.url.path == '/screenshot') {
            screenshotUrls.add(request.url);
            return http.Response.bytes(png, 200);
          }
          moveRequests.add(request);
          moves.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"ok":true}', 200);
        }));
    addTearDown(a.dispose);
    await a.health();
    bool hasFrame() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<RemoteFramePainter>()
        .isNotEmpty;
    Future<void> waitForFrame() async {
      // Frame decoding needs real time, which varies under load; wait until
      // a frame is shown instead of assuming one decode window is enough.
      for (var i = 0; i < 10 && !hasFrame(); i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
      }
    }

    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    await tester.pump();
    await waitForFrame();
    Rect crop() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<RemoteFramePainter>()
        .single
        .source;
    expect(crop(), const Rect.fromLTWH(0, 0, 192, 108));
    expect(screenshotUrls.first.queryParameters,
        {'monitor': '1', 'format': 'jpeg', 'quality': '70', 'scale': '0.5'});
    // The entire 16:9 display fits at 800x450 without cropping.
    final remote = find.byKey(const ValueKey('remote-half'));
    expect(tester.getSize(remote), const Size(800, 450));
    for (final entry in <Offset, Offset>{
      Offset.zero: const Offset(0, 0),
      const Offset(400, 225): const Offset(960, 540),
      const Offset(799, 449): const Offset(1918, 1078),
      const Offset(0, 449): const Offset(0, 1078),
    }.entries) {
      await tester.tapAt(tester.getTopLeft(remote) + entry.key);
      await tester.pump();
      expect(moveRequests.last.url.path, '/click');
      expect(moves.last['x'], entry.value.dx);
      expect(moves.last['y'], entry.value.dy);
    }
    // A narrow viewport still shows all four image edges.
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    for (final entry in <Offset, Offset>{
      Offset.zero: const Offset(0, 0),
      const Offset(200, 112.5): const Offset(960, 540),
      const Offset(399, 224): const Offset(1915, 1075),
    }.entries) {
      await tester.tapAt(tester.getTopLeft(remote) + entry.key);
      await tester.pump();
      expect(moves.last['x'], entry.value.dx);
      expect(moves.last['y'], entry.value.dy);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pump();
    final dynamic state = tester.state(find.byType(RemotePage));
    state.cursor = const Offset(100, 200);
    moveRequests.clear();
    moves.clear();

    tester
        .widget<KeyboardSurface>(find.byType(KeyboardSurface))
        .onMove(const Offset(20, -10));
    await tester.pump();
    expect(moveRequests, hasLength(1));
    expect(moveRequests.single.method, 'POST');
    expect(moveRequests.single.url.path, '/move');
    final padSize = tester.getSize(find.byType(KeyboardSurface));
    expect(moves.last['x'], (100 + 20 * 1920 / padSize.width).round());
    expect(moves.last['y'], (200 - 10 * 1080 / padSize.height).round());
    expect(moves.last.containsKey('relative'), isFalse);
    await tester.tap(find.byTooltip('Điều khiển'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Màn hình 2'));
    await tester.pumpAndSettle();
    // After the switch the new frame arrives one poll cycle later (the
    // in-flight frame for the old monitor finishes first, then the
    // zero-delay timer starts a poll for the new monitor, whose frame
    // needs a real-time decode). Decode time varies under load, so wait
    // until the new frame is shown instead of assuming a fixed number
    // of decode windows.
    for (var i = 0;
        i < 10 &&
            !(screenshotUrls.isNotEmpty &&
                screenshotUrls.last.queryParameters['monitor'] == '0' &&
                hasFrame());
        i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(screenshotUrls.last.queryParameters['monitor'], '0');
    expect(crop().left, 0);
    expect(crop().top, 0);
    expect(crop().width, closeTo(192, 0.000001));
    expect(crop().height, closeTo(108, 0.000001));
    tester
        .widget<KeyboardSurface>(find.byType(KeyboardSurface))
        .onMove(const Offset(-20, 10));
    await tester.pump();
    expect(moves.last['x'], (-1152 - 20 * 1536 / padSize.width).round());
    expect(moves.last['y'], (432 + 10 * 864 / padSize.height).round());
    tester
        .widget<KeyboardSurface>(find.byType(KeyboardSurface))
        .onMove(const Offset(-10000, 10000));
    await tester.pump();
    expect(moves.last['x'], -1920);
    expect(moves.last['y'], 863);
    // Selected display disappears: use virtual bounds rather than rejecting input.
    a.displays = [const DisplayInfo(1, -1920, 0, 3840, 1080)];
    tester
        .widget<KeyboardSurface>(find.byType(KeyboardSurface))
        .onMove(const Offset(2000, 100));
    await tester.pump();
    expect(moves.last['x'], 1919);
    expect(moves.last['y'], 1079);
    expect(find.textContaining('Agent cần metadata'), findsNothing);
    expect(moveRequests.map((r) => r.url.path), everyElement('/move'));
    expect(moveRequests.map((r) => r.method), everyElement('POST'));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Negative cursor from health is used without guessing screen center',
      (tester) async {
    final commands = <Map<String, dynamic>>[];
    final a = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response(
                jsonEncode({
                  'ok': true,
                  'width': 1920,
                  'height': 1080,
                  'cursorX': -1300,
                  'cursorY': 250,
                  'screens': [
                    {
                      'primary': true,
                      'x': -1920,
                      'y': 0,
                      'width': 1536,
                      'height': 864
                    },
                    {
                      'primary': false,
                      'x': 0,
                      'y': 0,
                      'width': 1920,
                      'height': 1080
                    },
                  ],
                }),
                200);
          }
          if (request.method == 'GET') return http.Response('no frame', 503);
          commands.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"ok":true}', 200);
        }));
    addTearDown(a.dispose);
    await a.health();
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    tester
        .widget<KeyboardSurface>(find.byType(KeyboardSurface))
        .onMove(const Offset(25, -15));
    await tester.pump();
    final pad = tester.getSize(find.byType(KeyboardSurface));
    expect(commands.single['x'], (-1300 + 25 * 1536 / pad.width).round());
    expect(commands.single['y'], (250 - 15 * 864 / pad.height).round());
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Direct keys send text and modifier chords without text input',
      (tester) async {
    final requests = <http.Request>[];
    final a = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('no frame', 503);
          requests.add(request);
          return http.Response('{}', 200);
        }));
    addTearDown(a.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Dán'), findsNothing);
    expect(find.text('Dán trên PC'), findsNothing);
    await tester.tap(find.text('Q'));
    await tester.pump();
    expect(requests.single.url.path, '/type');
    expect(jsonDecode(requests.single.body)['text'], 'q');
    await tester.tap(find.text('Ctrl').first);
    await tester.tap(find.text('C'));
    await tester.pump();
    expect(requests.last.url.path, '/key');
    expect(jsonDecode(requests.last.body)['keys'], '^c');
    final dynamic state = tester.state(find.byType(RemotePage));
    expect(state.modifiers, isEmpty);
    await tester.tap(find.text('V'));
    await tester.pump();
    expect(requests.last.url.path, '/type');
    expect(jsonDecode(requests.last.body)['text'], 'v');
    await tester.tap(find.text('Ctrl').first);
    await tester.pump();
    await tester.tap(find.text('Ctrl').first);
    await tester.pump();
    expect(state.modifiers, isEmpty);
    await tester.tap(find.text('Ctrl').first);
    await tester.pump();
    await tester.tap(find.text('Alt').first);
    await tester.pump();
    await tester.tap(find.text('Del'));
    await tester.pump();
    expect(jsonDecode(requests.last.body)['keys'], '^%{DEL}');
    expect(state.modifiers, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Laptop rows and mouse buttons send the expected commands',
      (tester) async {
    final requests = <http.Request>[];
    final a = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('no frame', 503);
          requests.add(request);
          return http.Response('{}', 200);
        }));
    addTearDown(a.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    final rows = [
      ['Esc', for (var i = 1; i <= 12; i++) 'F$i', 'Del'],
      [...'`1234567890-='.split(''), 'Backspace'],
      ['Tab', ...'QWERTYUIOP[]'.split(''), r'\'],
      ['Caps', ..."ASDFGHJKL;'".split(''), 'Enter'],
      ['Shift', ...'ZXCVBNM,./'.split(''), 'Shift'],
      ['Ctrl', 'Win', 'Alt', 'Space', 'Alt', 'Ctrl', '←', '↑', '↓', '→'],
      ['Click trái', 'Click phải'],
    ];
    for (var i = 0; i < rows.length; i++) {
      expect(
          tester
              .widgetList<Text>(find.descendant(
                  of: find.byKey(ValueKey('keyboard-row-$i')),
                  matching: find.byType(Text)))
              .map((w) => w.data)
              .toList(),
          rows[i]);
    }
    final dynamic state = tester.state(find.byType(RemotePage));
    state.cursor = const Offset(123, 234);
    for (final button in ['left', 'right']) {
      await tester
          .tap(find.text(button == 'left' ? 'Click trái' : 'Click phải'));
      await tester.pump();
      expect(requests.last.url.path, '/click');
      expect(jsonDecode(requests.last.body), {
        'button': button,
        'x': 123,
        'y': 234,
        'monitor': 1,
      });
    }
    for (final label in ['F1', 'F12', 'Backspace', 'Enter', 'Del']) {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(requests.last.url.path, '/key');
      expect(
          jsonDecode(requests.last.body)['keys'],
          {
            'F1': '{F1}',
            'F12': '{F12}',
            'Backspace': '{BACKSPACE}',
            'Enter': '{ENTER}',
            'Del': '{DEL}',
          }[label]);
    }
    for (final label in ['Caps', 'Shift']) {
      final count = requests.length;
      await tester.tap(find.text(label).first);
      await tester.pump();
      expect(requests.length, count);
      await tester.tap(find.text('C'));
      await tester.pump();
      expect(jsonDecode(requests.last.body)['keys'], '+c');
      expect(state.modifiers, isEmpty);
      await tester.tap(find.text('C'));
      await tester.pump();
      expect(requests.last.url.path, '/type');
      expect(jsonDecode(requests.last.body)['text'], 'c');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Win arms one-shot chords and a second tap sends standalone Win',
      (tester) async {
    final requests = <http.Request>[];
    final a = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('no frame', 503);
          requests.add(request);
          return http.Response('{"ok":true}', 200);
        }));
    addTearDown(a.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    final dynamic state = tester.state(find.byType(RemotePage));
    for (final letter in ['R', 'D', 'L']) {
      await tester.tap(find.text('Win'));
      await tester.pump();
      expect(state.modifiers, contains('Win'));
      await tester.tap(find.text(letter));
      await tester.pump();
      expect(requests.last.url.path, '/key');
      expect(jsonDecode(requests.last.body)['keys'], 'Win+$letter');
      expect(state.modifiers, isEmpty);
    }
    await tester.tap(find.text('Win'));
    await tester.pump();
    await tester.tap(find.text('Win'));
    await tester.pump();
    expect(jsonDecode(requests.last.body)['keys'], 'Win');
    expect(state.modifiers, isEmpty);
    expect(find.text('Phím Win chưa được agent hỗ trợ'), findsNothing);
    await tester.tap(find.text('V'));
    await tester.pump();
    expect(requests.last.url.path, '/type');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'All key kinds highlight on down and reset on up, cancel and drag',
      (tester) async {
    final a = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(a.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    Color? color(String label) => (tester
            .widget<Container>(find
                .ancestor(
                    of: find.text(label).first,
                    matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration)
        .color;
    for (final label in [
      'Q',
      'Ctrl',
      'Win',
      'Click trái',
      'Click phải',
      'Del'
    ]) {
      final before = color(label);
      final gesture =
          await tester.startGesture(tester.getCenter(find.text(label).first));
      await tester.pump();
      expect(color(label), const Color(0xff8b929e));
      await gesture.cancel();
      await tester.pump();
      expect(color(label), before);
      final tap =
          await tester.startGesture(tester.getCenter(find.text(label).first));
      await tester.pump();
      await tap.up();
      await tester.pump();
      expect(color(label), isNot(const Color(0xff8b929e)));
    }
    final drag = await tester.startGesture(tester.getCenter(find.text('Q')));
    await tester.pump();
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(color('Q'), const Color(0xff292b30));
    await drag.up();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Remote follows display aspect ratio with a complete floating menu',
      (tester) async {
    final a = Agent(baseUrl: defaultBaseUrl, mock: true);
    await a.health();
    addTearDown(a.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    for (final size in [
      const Size(900, 1200),
      const Size(1200, 900),
      const Size(360, 480)
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pump();
      final remote = find.byKey(const ValueKey('remote-half'));
      final keyboard = find.byKey(const ValueKey('keyboard-half'));
      final d = a.displays.first;
      final height = size.width * d.height / d.width;
      expect(tester.getSize(remote), Size(size.width, height));
      expect(tester.getSize(keyboard), Size(size.width, size.height - height));
      expect(tester.getTopLeft(remote), Offset.zero);
      expect(tester.getTopLeft(keyboard).dy, height);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(900, 1200);
    await tester.pump();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.tap(find.byTooltip('Điều khiển'));
    await tester.pumpAndSettle();
    for (final label in [
      'Màn hình 1',
      'Màn hình 2',
      'Vừa màn hình',
      '1:1',
      'Chạm tuyệt đối',
      'Bật/tắt lớp trackpad',
      'Bật/tắt bàn phím',
      'Ngủ',
      'Khởi động lại',
      'Tắt máy',
      'Cài đặt',
      'Ngắt kết nối',
      'Nhật ký mock'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Chạm tuyệt đối'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Điều khiển'));
    await tester.pumpAndSettle();
    expect(find.text('Trackpad tương đối'), findsOneWidget);
    await tester.tap(find.text('Bật/tắt bàn phím'));
    await tester.pumpAndSettle();
    expect(find.text('Q'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('keyboard-half'))).height,
        1200 - 900 * a.displays.first.height / a.displays.first.width);
    await tester.pumpWidget(const SizedBox());
  });
  for (final action in ['sleep', 'restart', 'shutdown']) {
    testWidgets('Power $action posts to /power after confirmation',
        (tester) async {
      final requests = <http.Request>[];
      final a = Agent(
          baseUrl: defaultBaseUrl,
          client: MockClient((request) async {
            if (request.method == 'GET') return http.Response('no frame', 503);
            requests.add(request);
            return http.Response('{"ok":true}', 200);
          }));
      addTearDown(a.dispose);
      await tester.pumpWidget(
          MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
      final label = {
        'sleep': 'Ngủ',
        'restart': 'Khởi động lại',
        'shutdown': 'Tắt máy'
      }[action]!;
      await tester.tap(find.byTooltip('Điều khiển'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      if (action != 'sleep') {
        expect(requests, isEmpty);
        await tester.tap(find.text('Xác nhận'));
        await tester.pumpAndSettle();
      }
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/power');
      expect(jsonDecode(requests.single.body)['action'], action);
      expect(find.text('Đã gửi lệnh ${label.toLowerCase()}'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('Power errors show agent error without success notice',
      (tester) async {
    final a = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('no frame', 503);
          return http.Response('{"ok":false,"error":"power failed"}', 500);
        }));
    addTearDown(a.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    await tester.tap(find.byTooltip('Điều khiển'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ngủ'));
    await tester.tap(find.text('Ngủ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.textContaining('power failed'), findsOneWidget);
    expect(find.text('Đã gửi lệnh ngủ'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Shutdown requires two approvals; cancel sends nothing',
      (tester) async {
    final a = Agent(baseUrl: defaultBaseUrl, mock: true);
    await a.health();
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tắt máy'));
    await tester.tap(find.text('Tắt máy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.text('Xác nhận lần 2'), findsOneWidget);
    expect(a.log.value.where((s) => s.contains('/power')), isEmpty);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(a.log.value.where((s) => s.contains('/power')), isEmpty);
    await tester.pumpWidget(const SizedBox());
    a.dispose();
  });
}
