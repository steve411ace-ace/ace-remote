import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:ace_remote/agent.dart';
import 'package:ace_remote/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Home shows only the supported Windows PC', (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox(),
            onLock: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Mac\u0042ook'), findsNothing);
    expect(find.textContaining('Chưa h\u1ed7 trợ'), findsNothing);
    expect(find.byType(Card), findsOneWidget);
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
          .buffer.asUint8List();
      image.dispose();
      picture.dispose();
      return bytes;
    }))!;
    var requests = 0;
    final nextFrame = Completer<http.Response>();
    final agent = Agent(baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
      requests++;
      if (requests == 1) return http.Response('frame unavailable', 503);
      if (requests == 2) return http.Response.bytes(png, 200);
      return nextFrame.future;
    }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000)));
    await tester.pump();
    final dynamic state = tester.state(find.byType(RemotePage));
    expect(state.failures, 1);
    expect(state.error, isNull);
    expect(state.delay, 2000);
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(requests, 2);
    expect(state.failures, 0);
    expect(state.delay, 1000);
    expect(state.error, isNull);
    expect(tester.widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter).whereType<RemoteFramePainter>(), isNotEmpty);
    expect(find.text('Ảnh: 1.0/giây'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(requests, 3);
    await tester.pumpWidget(const SizedBox());
    nextFrame.complete(http.Response('frame unavailable', 503));
    await tester.pump();
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
  testWidgets('Keyboard tap versus move and two-finger scroll send distinct commands',
      (tester) async {
    final requests = <http.Request>[];
    final agent = Agent(baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
      if (request.method == 'GET') return http.Response('no frame', 503);
      requests.add(request);
      return http.Response('{}', 200);
    }));
    agent.displays = [const DisplayInfo(1, 0, 0, 1920, 1080)];
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000)));
    final q = tester.getCenter(find.text('q'));
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
    expect(move['x'], 20);
    expect(move['y'], 10);
    expect(move.containsKey('relative'), isFalse);
    requests.clear();

    final first = await tester.startGesture(q, pointer: 11);
    final second = await tester.startGesture(q + const Offset(30, 0), pointer: 12);
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

    await tester.tap(find.byType(TextField));
    await tester.pump();
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
    await tester.tap(find.text('Click Phải'));
    await tester.pump();
    await tester.pump();
    expect(screenshot.isCompleted, isFalse);
    expect(screenshotRequests, hasLength(1));
    expect(screenshotRequests.single.url.path, '/screenshot');
    expect(screenshotRequests.single.url.hasQuery, isFalse);
    expect(commands, hasLength(2));
    expect(find.textContaining('Lệnh điều khiển bị gián đoạn'), findsOneWidget);
    await tester.tap(find.text('Màn hình 2'));
    await tester.pump();
    expect(find.text('Màn hình 2 ✓'), findsOneWidget);
    expect(find.text('ace • Màn hình 2'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pump();
    await tester.pump();
    expect(commands, hasLength(3));
    expect(commands.last['monitor'], 1);
    expect(find.textContaining('Lệnh điều khiển bị gián đoạn'), findsNothing);
    // A failed frame leaves the selected tab and input controls available.
    screenshot.complete(http.Response('frame unavailable', 503));
    await tester.pump();
    await tester.pump();
    expect(find.text('Màn hình 2 ✓'), findsOneWidget);
    expect(find.textContaining('Lệnh điều khiển bị gián đoạn'), findsNothing);
    await tester.tap(find.text('Click Phải'));
    await tester.pump();
    expect(commands.last['monitor'], 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Real health cursor drives absolute moves; tabs change crop',
      (tester) async {
    final png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(384, 108);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      return png;
    }))!;
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
                      'primary': true,
                      'x': 0,
                      'y': 0,
                      'width': 1920,
                      'height': 1080
                    },
                    {
                      'primary': false,
                      'x': -1920,
                      'y': 0,
                      'width': 1536,
                      'height': 864
                    },
                  ],
                }),
                200);
          }
          if (request.url.path == '/screenshot')
            return http.Response.bytes(png, 200);
          moveRequests.add(request);
          moves.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"ok":true}', 200);
        }));
    addTearDown(a.dispose);
    await a.health();
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    Rect crop() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<RemoteFramePainter>()
        .single
        .source;
    expect(crop(), const Rect.fromLTWH(192, 0, 192, 108));
    tester
        .widget<KeyboardSurface>(find.byType(KeyboardSurface))
        .onMove(const Offset(20, -10));
    await tester.pump();
    expect(moveRequests, hasLength(1));
    expect(moveRequests.single.method, 'POST');
    expect(moveRequests.single.url.path, '/move');
    expect(moves.last['x'], 120);
    expect(moves.last['y'], 190);
    expect(moves.last.containsKey('relative'), isFalse);
    await tester.tap(find.text('Màn hình 2'));
    await tester.pump();
    expect(crop().left, 0);
    expect(crop().top, 0);
    expect(crop().width, closeTo(153.6, 0.000001));
    expect(crop().height, closeTo(86.4, 0.000001));
    tester
        .widget<KeyboardSurface>(find.byType(KeyboardSurface))
        .onMove(const Offset(-20, 10));
    await tester.pump();
    expect(moves.last['x'], -1172);
    expect(moves.last['y'], 442);
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
    expect(moves.last['x'], 80);
    expect(moves.last['y'], 963);
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
    expect(commands.single['x'], -1275);
    expect(commands.single['y'], 235);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Typing sends raw Unicode, reports agent error; PC paste uses Ctrl+V',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    var failType = false;
    final a = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('no frame', 503);
          requests.add(request);
          if (failType && request.url.path == '/type') {
            return http.Response(
                '{"ok":false,"error":"SendKeys layout failure"}', 500);
          }
          return http.Response('{"ok":true}', 200);
        }));
    addTearDown(a.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    await tester.enterText(find.byType(TextField), 'Tiếng Việt +^%~(){}');
    await tester.tap(find.byTooltip('Gõ'));
    await tester.pump();
    expect(requests.last.url.path, '/type');
    expect(jsonDecode(requests.last.body)['text'], 'Tiếng Việt +^%~(){}');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.ensureVisible(find.text('Dán trên PC'));
    await tester.tap(find.text('Dán trên PC'));
    await tester.pump();
    expect(requests.last.url.path, '/key');
    expect(jsonDecode(requests.last.body)['keys'], '^v');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': 'Dán từ điện thoại +{} Việt'};
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.text('Dán'));
    await tester.pump();
    await tester.pump();
    expect(requests.last.url.path, '/type');
    expect(
        jsonDecode(requests.last.body)['text'], 'Dán từ điện thoại +{} Việt');
    failType = true;
    await tester.enterText(find.byType(TextField), 'Giữ lại khi lỗi');
    await tester.tap(find.byTooltip('Gõ'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('SendKeys layout failure'), findsWidgets);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Giữ lại khi lỗi');
    expect(requests.where((r) => r.url.path == '/type'), hasLength(4));
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
