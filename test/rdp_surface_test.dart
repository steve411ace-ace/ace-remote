import 'dart:math';

import 'package:ace_remote/agent.dart';
import 'package:ace_remote/main.dart';
import 'package:ace_remote/rdp_connections.dart';
import 'package:ace_remote/rdp_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ace_remote/rdp_credentials.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('saved username and password restore; password stays obscured', (tester) async {
    FlutterSecureStorage.setMockInitialValues({rdpUsernameKey: 'saved-user', rdpPasswordKey: 'saved-secret'});
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RdpConnectionPane())));
    await tester.pumpAndSettle();
    final userField = tester.widget<TextField>(find.byKey(const ValueKey('rdp-username')));
    expect(userField.controller!.text, 'saved-user');
    final field = tester.widget<TextField>(find.byKey(const ValueKey('rdp-password')));
    expect(field.obscureText, isTrue);
    expect(field.controller!.text, 'saved-secret');
    // The "Quên mật khẩu" button is gone (An asked to remove it): the saved
    // credentials stay until the app data is cleared / the app is removed.
    expect(find.text('Quên mật khẩu'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('username and password saved only after native connection success', (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/19');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'status' ? {'state': 'idle'} : null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = RdpController();
    await controller.attach(19);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RdpConnectionPane(controller: controller))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('rdp-username')), 'user');
    await tester.enterText(find.byKey(const ValueKey('rdp-password')), 'success-secret');
    await tester.ensureVisible(find.text('Kết nối'));
    await tester.tap(find.text('Kết nối'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await storage.read(key: rdpUsernameKey, aOptions: rdpStorageOptions), isNull);
    expect(await storage.read(key: rdpPasswordKey, aOptions: rdpStorageOptions), isNull);
    controller.value = {'state': 'connected'};
    await tester.pumpAndSettle();
    expect(await storage.read(key: rdpUsernameKey, aOptions: rdpStorageOptions), 'user');
    expect(await storage.read(key: rdpPasswordKey, aOptions: rdpStorageOptions), 'success-secret');
    controller.value = {'state': 'connected', 'resizeFailure': 'DISP unavailable'};
    await tester.pump();
    // A DISP resize failure must not drop the session: the login form stays
    // hidden and the remote surface stays up (no buttons on it any more).
    expect(find.byType(RdpSurface), findsOneWidget);
    expect(find.text('Kết nối lại'), findsNothing);
    expect(find.text('Kết nối'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('credentials refill from storage after disconnect', (tester) async {
    FlutterSecureStorage.setMockInitialValues({rdpUsernameKey: 'saved-user', rdpPasswordKey: 'saved-secret'});
    const channel = MethodChannel('vn.aceremote.app/rdp/21');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'status' ? {'state': 'idle'} : null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = RdpController();
    await controller.attach(21);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RdpConnectionPane(controller: controller))));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('rdp-username'))).controller!.text, 'saved-user');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('rdp-password'))).controller!.text, 'saved-secret');
    await tester.enterText(find.byKey(const ValueKey('rdp-username')), 'user');
    await tester.ensureVisible(find.text('Kết nối'));
    await tester.tap(find.text('Kết nối'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    controller.value = {'state': 'connected'};
    await tester.pumpAndSettle();
    // The username typed for this successful connect is now the saved one.
    expect(await storage.read(key: rdpUsernameKey, aOptions: rdpStorageOptions), 'user');
    controller.value = {'state': 'disconnected'};
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('rdp-username'))).controller!.text, 'user');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('rdp-password'))).controller!.text, 'saved-secret');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('RDP keyboard sends VK chords and never HTTP', (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/0');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var requests = 0;
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          requests++;
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.sendKey(0x41, true); // Unattached controller is a no-op.
    await controller.sendCursor(1, 2, 0x800);
    await controller.clickAtLastPosition('left');
    await controller.attach(0);
    // attach() re-sends the current touch mode ('mode'); not part of this test.
    calls.clear();
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', {'state': 'connected'})),
        (_) {});
    await tester.pump();
    Future<void> tap(String label) async {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }

    for (final label in ['A', 'Enter', 'Esc', 'Ctrl', 'C']) {
      await tap(label);
    }
    expect(calls.map((c) => c.method), everyElement('key'));
    expect(calls.map((c) => c.arguments).toList(), [
      {'vk': 0x41, 'down': true},
      {'vk': 0x41, 'down': false},
      {'vk': 0x0d, 'down': true},
      {'vk': 0x0d, 'down': false},
      {'vk': 0x1b, 'down': true},
      {'vk': 0x1b, 'down': false},
      {'vk': 0xa2, 'down': true},
      {'vk': 0x43, 'down': true},
      {'vk': 0x43, 'down': false},
      {'vk': 0xa2, 'down': false},
    ]);
    calls.clear();
    await tap('Win');
    expect(calls, isEmpty);
    await tap('Win');
    expect(calls.map((c) => c.arguments).toList(), [
      {'vk': 0x15b, 'down': true},
      {'vk': 0x15b, 'down': false},
    ]);
    calls.clear();
    expect(find.text('Click trái'), findsNothing);
    expect(find.text('Click phải'), findsNothing);
    expect(find.byKey(const ValueKey('keyboard-row-6')), findsNothing);
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Caps Lock toggles with VK_CAPITAL and stays on across keys',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/22');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(22);
    // attach() re-sends the current touch mode ('mode'); not part of this test.
    calls.clear();
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', {'state': 'connected'})),
        (_) {});
    await tester.pump();
    final dynamic state = tester.state(find.byType(RemotePage));
    expect(state.capsLockOn, isFalse);
    Color? capsColor() => ((tester
            .widget<Container>(find
                .ancestor(
                    of: find.text('Caps').first,
                    matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration)
        .gradient as LinearGradient?)
        ?.colors
        .first;
    Future<void> tap(String label) async {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }

    // First Caps press: one VK_CAPITAL tap, state on, key highlighted.
    await tap('Caps');
    expect(calls.map((c) => c.arguments).toList(), [
      {'vk': 0x14, 'down': true},
      {'vk': 0x14, 'down': false},
    ]);
    expect(state.capsLockOn, isTrue);
    expect(capsColor(), const Color(0xff33c0af));
    // A letter key does not clear Caps Lock (unlike Shift one-shot).
    calls.clear();
    await tap('A');
    expect(calls.map((c) => c.arguments).toList(), [
      {'vk': 0x41, 'down': true},
      {'vk': 0x41, 'down': false},
    ]);
    expect(state.capsLockOn, isTrue);
    expect(capsColor(), const Color(0xff33c0af));
    // Second Caps press: toggle off, highlight gone.
    calls.clear();
    await tap('Caps');
    expect(calls.map((c) => c.arguments).toList(), [
      {'vk': 0x14, 'down': true},
      {'vk': 0x14, 'down': false},
    ]);
    expect(state.capsLockOn, isFalse);
    expect(capsColor(), const Color(0xff3a3d44));
    // Shift is still a one-shot modifier and does not touch Caps Lock.
    calls.clear();
    await tap('Shift');
    expect(calls, isEmpty);
    await tap('A');
    expect(calls.map((c) => c.arguments).toList(), [
      {'vk': 0xa0, 'down': true},
      {'vk': 0x41, 'down': true},
      {'vk': 0x41, 'down': false},
      {'vk': 0xa0, 'down': false},
    ]);
    expect(state.capsLockOn, isFalse);
    expect(state.modifiers, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RDP status preserves native physical pixels across resize', (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/15');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var pixels = <String, dynamic>{'state': 'idle', 'widthPx': 1600, 'heightPx': 600};
    messenger.setMockMethodCallHandler(channel, (call) async => pixels);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = RdpController();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.attach(15);
    expect(controller.value['widthPx'], 1600);
    expect(controller.value['heightPx'], 600);
    pixels = {'state': 'connected', 'widthPx': 1200, 'heightPx': 800};
    expect(await controller.status(), pixels);
  });

  testWidgets('RDP waiting page pins the keyboard to the bottom and the remote fills the rest',
      (tester) async {
    var requests = 0;
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((request) async {
          requests++;
          throw StateError('Waiting RDP must not contact the HTTP agent');
        }));
    addTearDown(agent.dispose);
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 2;
    for (final size in [const Size(1600, 1200), const Size(1200, 1600)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
      await tester.pump();
      final remote = tester.getRect(find.byKey(const ValueKey('remote-half')));
      final keyboard =
          tester.getRect(find.byKey(const ValueKey('keyboard-half')));
      // Step 26, item 3: no more fixed 50/50 split. The keyboard is a
      // fixed-height strip (6 rows + 8dp padding) pinned to the bottom
      // edge; the remote screen takes all the remaining space above it.
      final logical = Size(size.width / 2, size.height / 2);
      final byWidth =
          (logical.width / 16.25 * 1.15).clamp(44.0, 64.0).toDouble();
      final rowHeight = min(byWidth, (logical.height - 8) / 6);
      final kbHeight = rowHeight * 6 + 8;
      expect(keyboard.height, closeTo(kbHeight, 1.0));
      expect(remote.height, closeTo(logical.height - kbHeight, 1.0));
      expect(keyboard.bottom, closeTo(logical.height, 1.0));
      expect(keyboard.top, closeTo(remote.bottom, 1.0));
      expect(remote.width, size.width / 2);
      await tester.tap(find.text('Esc'));
      await tester.pump(const Duration(seconds: 2));
      expect(requests, 0);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('RDP form sends credentials and follows native lifecycle', (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/0');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller = tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(0);
    await tester.pump();
    expect(find.text('Kết nối'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('rdp-host'))).controller!.text, '100.101.127.41');
    await tester.enterText(find.byKey(const ValueKey('rdp-host')), 'rdp.example');
    await tester.enterText(find.byKey(const ValueKey('rdp-username')), 'test-user');
    await tester.enterText(find.byKey(const ValueKey('rdp-password')), 'test-secret');
    await tester.ensureVisible(find.text('Kết nối'));
    await tester.tap(find.text('Kết nối'));
    await tester.pump();
    expect(calls.where((call) => call.method == 'connect'), isEmpty);
    await tester.pump(const Duration(milliseconds: 399));
    expect(calls.where((call) => call.method == 'connect'), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls.last.method, 'connect');
    expect(calls.last.arguments, {'host': 'rdp.example', 'port': 3389, 'username': 'test-user', 'password': 'test-secret'});
    expect(tester.widget<TextField>(find.byKey(const ValueKey('rdp-password'))).controller!.text, isEmpty);
    Future<void> event(Map<String, dynamic> state) async {
      await messenger.handlePlatformMessage(channel.name, const StandardMethodCodec().encodeMethodCall(MethodCall('state', state)), (_) {});
      await tester.pump();
    }
    await event({'state': 'connecting'});
    expect(find.text('Đang kết nối…'), findsOneWidget);
    await tester.tap(find.text('Ngắt'));
    await tester.pump();
    expect(calls.last.method, 'disconnect');
    await event({'state': 'disconnecting'});
    expect(find.text('Đang ngắt kết nối…'), findsOneWidget);
    await event({'state': 'connected'});
    // Connected: the login form is hidden and the remote surface is up.
    // There is no "Đã kết nối" pill and no disconnect button any more
    // (redesign 04:03); leaving is via Android Back, covered by the
    // Back test in rdp_connections_test.dart.
    expect(find.byType(RdpSurface), findsOneWidget);
    expect(find.byKey(const ValueKey('rdp-password')), findsNothing);
    await event({'state': 'failed', 'error': 'Test failure', 'authAttempted': true});
    expect(find.text('Test failure'), findsOneWidget);
    expect(find.text('Kết nối lại'), findsOneWidget);
    expect(find.text('Đã đi qua callback xác thực; chưa xác định nguyên nhân.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('rdp-password'))).controller!.text, isEmpty);
    await event({'state': 'failed', 'authAttempted': false});
    expect(find.text('Chưa đi qua callback xác thực; chưa xác định nguyên nhân.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('connected remote screen shows no control buttons', (tester) async {
    // Redesign 04:03: the remote screen has no buttons at all — no mode /
    // keyboard / disconnect / chevron buttons and no "Đã kết nối" pill.
    // Trackpad mode and keyboard visibility are per-connection settings from
    // the Edit screen now, not buttons on the remote screen.
    const channel = MethodChannel('vn.aceremote.app/rdp/23');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = RdpController();
    await controller.attach(23);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RdpConnectionPane(controller: controller))));
    await tester.pumpAndSettle();
    controller.value = {'state': 'connected'};
    await tester.pump();
    expect(find.byType(RdpSurface), findsOneWidget);
    expect(find.text('Đã kết nối'), findsNothing);
    expect(find.byTooltip('Chế độ trackpad'), findsNothing);
    expect(find.byTooltip('Chế độ chạm'), findsNothing);
    expect(find.byTooltip('Ẩn bàn phím'), findsNothing);
    expect(find.byTooltip('Hiện bàn phím'), findsNothing);
    expect(find.byTooltip('Ngắt kết nối'), findsNothing);
    expect(find.byTooltip('Ẩn điều khiển'), findsNothing);
    expect(find.byTooltip('Hiện điều khiển'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('pane applies the saved connection trackpad and keyboard settings', (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/24');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = RdpController();
    await controller.attach(24);
    const connection = RdpConnection(
        id: 'pc-trackpad',
        name: 'PC trackpad',
        host: '10.0.0.5',
        port: 3389,
        trackpadMode: true,
        keyboardVisible: false);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: RdpConnectionPane(controller: controller, initialConnection: connection))));
    await tester.pumpAndSettle();
    expect(controller.trackpadMode.value, isTrue);
    expect(controller.keyboardVisible.value, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('RDP keyboard stays visible in trackpad mode and swipes move the cursor', (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/0');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(0);
    await tester.pump();
    // The keyboard stays visible in both modes (no blank trackpad surface).
    expect(find.text('Esc'), findsOneWidget);
    expect(find.byKey(const ValueKey('rdp-trackpad')), findsNothing);
    calls.clear();
    await controller.setTrackpadMode(true);
    await tester.pump();
    expect(find.text('Esc'), findsOneWidget);
    expect(find.byKey(const ValueKey('rdp-trackpad')), findsNothing);
    expect(calls.map((c) => c.method), contains('mode'));
    expect(calls.lastWhere((c) => c.method == 'mode').arguments,
        {'trackpad': true});
    // Drag across the keyboard moves the cursor relatively, no key fires.
    calls.clear();
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', {'state': 'connected'})),
        (_) {});
    await tester.pump();
    await tester.drag(find.text('A'), const Offset(60, 0));
    await tester.pump();
    expect(calls.map((c) => c.method), contains('moveRelative'));
    final move = calls.firstWhere((c) => c.method == 'moveRelative');
    expect((move.arguments as Map)['dx'], greaterThan(0));
    expect(calls.where((c) => c.method == 'key'), isEmpty);
    // Quick tap on a key still types it.
    calls.clear();
    await tester.tap(find.text('A'));
    await tester.pump();
    expect(calls.map((c) => c.arguments).toList(), [
      {'vk': 0x41, 'down': true},
      {'vk': 0x41, 'down': false},
    ]);
    // Two-finger tap on the keyboard clicks right, no key fires.
    calls.clear();
    final center = tester.getCenter(find.text('A'));
    final first = await tester.startGesture(center);
    final second = await tester.startGesture(center + const Offset(20, 0));
    await first.up();
    await second.up();
    await tester.pump();
    expect(calls.map((c) => c.method), contains('click'));
    expect(calls.lastWhere((c) => c.method == 'click').arguments,
        {'button': 'right'});
    expect(calls.where((c) => c.method == 'key'), isEmpty);
    // Back to touch mode: the keyboard still swipes to move the cursor.
    await controller.setTrackpadMode(false);
    await tester.pump();
    expect(find.text('Esc'), findsOneWidget);
    calls.clear();
    await tester.drag(find.text('A'), const Offset(60, 0));
    await tester.pump();
    expect(calls.map((c) => c.method), contains('moveRelative'));
    expect(calls.where((c) => c.method == 'key'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hiding the keyboard lets the remote fill the screen', (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1600, 1200);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    await tester.pump();
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    var remote = tester.getRect(find.byKey(const ValueKey('remote-half')));
    var keyboard = tester.getRect(find.byKey(const ValueKey('keyboard-half')));
    // Step 26, item 3: 800x600 logical; row height follows the step 25
    // formula (56.6), so the keyboard strip is 6*56.6+8 = 347.7 tall
    // and the remote takes the remaining 252.3.
    expect(remote.height, closeTo(252.3, 1.0));
    expect(keyboard.height, closeTo(347.7, 1.0));
    controller.keyboardVisible.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey('keyboard-half')), findsNothing);
    remote = tester.getRect(find.byKey(const ValueKey('remote-half')));
    expect(remote.height, 600);
    controller.keyboardVisible.value = true;
    await tester.pump();
    remote = tester.getRect(find.byKey(const ValueKey('remote-half')));
    keyboard = tester.getRect(find.byKey(const ValueKey('keyboard-half')));
    expect(remote.height, closeTo(252.3, 1.0));
    expect(keyboard.height, closeTo(347.7, 1.0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Shift armed shows shifted labels and types the shown character',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/25');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(25);
    // attach() re-sends the current touch mode ('mode'); not part of this test.
    calls.clear();
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', {'state': 'connected'})),
        (_) {});
    await tester.pump();
    Future<void> tap(String label) async {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }

    // Unshifted labels first.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('@'), findsNothing);
    // Arm Shift: the number row shows its Shift characters.
    await tap('Shift');
    expect(find.text('@'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(find.text('!'), findsOneWidget);
    expect(find.text(')'), findsOneWidget);
    expect(find.text('_'), findsOneWidget);
    // Typing the key showing '@' sends Shift + the base '2' key, so
    // Windows receives '@'; the one-shot Shift then clears and the labels
    // revert to unshifted.
    calls.clear();
    await tap('@');
    expect(calls.map((c) => c.arguments).toList(), [
      {'vk': 0xa0, 'down': true},
      {'vk': 0x32, 'down': true},
      {'vk': 0x32, 'down': false},
      {'vk': 0xa0, 'down': false},
    ]);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('@'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RDP Left/Right mouse keys flank Space and click at the cursor',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/33');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(33);
    // attach() re-sends the current touch mode ('mode'); not part of this test.
    calls.clear();
    // Bottom row: 'Left' on the left of Space clicks left, 'Right' on the
    // right of Space clicks right (step 25, item 1); both Alt-sized.
    expect(
        tester
            .widgetList<Text>(find.descendant(
                of: find.byKey(const ValueKey('keyboard-row-5')),
                matching: find.byType(Text)))
            .map((w) => w.data)
            .toList(),
        ['Ctrl', 'Win', 'Alt', 'Left', 'Space', 'Right', 'Alt', 'Ctrl', '←', '↓', '→']);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
    // Not connected yet: a mouse-key tap sends nothing.
    await tester.tap(find.text('Left'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('Right'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', {'state': 'connected'})),
        (_) {});
    await tester.pump();
    // Each mouse key clicks at the cursor with its own button; no VK is
    // sent ('Left'/'Right' as key labels would be the VK_LEFT/VK_RIGHT
    // arrow keys, 0x125/0x127).
    for (final entry in {'Left': 'left', 'Right': 'right'}.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['click']);
      expect(calls.single.arguments, {'button': entry.value});
      calls.clear();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RDP arrow keys form an inverted T with equal up/down size',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/34');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(34);
    calls.clear();
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', {'state': 'connected'})),
        (_) {});
    await tester.pump();
    // ↑ sits at the end of the Shift row, above ↓; ← ↓ → stay on the
    // bottom row.
    List<String?> rowLabels(int index) => tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(ValueKey('keyboard-row-$index')),
            matching: find.byType(Text)))
        .map((w) => w.data)
        .toList();
    expect(rowLabels(4),
        ['Shift', ...'ZXCVBNM,./'.split(''), 'Shift', '↑', 'End']);
    expect(rowLabels(5), [
      'Ctrl',
      'Win',
      'Alt',
      'Left',
      'Space',
      'Right',
      'Alt',
      'Ctrl',
      '←',
      '↓',
      '→'
    ]);
    // ↑ and ↓ are the same size: full keys, no half-height (An's rule).
    Size keySize(String label) => tester.getSize(find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first);
    final up = keySize('↑');
    final down = keySize('↓');
    expect(up.width, closeTo(down.width, 1.0));
    expect(up.height, closeTo(down.height, 1.0));
    // Each arrow still sends its own VK.
    Future<void> tap(String label) async {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }

    for (final entry in {
      '↑': 0x126,
      '←': 0x125,
      '↓': 0x128,
      '→': 0x127,
    }.entries) {
      calls.clear();
      await tap(entry.key);
      expect(calls.map((c) => c.arguments).toList(), [
        {'vk': entry.value, 'down': true},
        {'vk': entry.value, 'down': false},
      ]);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RDP navigation column sends the right VKs', (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/35');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(35);
    calls.clear();
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', {'state': 'connected'})),
        (_) {});
    await tester.pump();
    // Step 24, item 6: navigation column at the far right — PgUp in the
    // number row, PgDn in the QWERTY row, Home in the ASDF row, End in
    // the Shift row (left of nothing; ↑ sits left of End). Del in the
    // F row was already there.
    List<String?> rowLabels(int index) => tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(ValueKey('keyboard-row-$index')),
            matching: find.byType(Text)))
        .map((w) => w.data)
        .toList();
    expect(rowLabels(0).last, 'Del');
    expect(rowLabels(1).last, 'PgUp');
    expect(rowLabels(2).last, 'PgDn');
    expect(rowLabels(3).last, 'Home');
    expect(rowLabels(4).last, 'End');
    Future<void> tap(String label) async {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }

    for (final entry in {
      // Step 25, item 2: the extended flag (0x100) — without it the
      // FreeRDP lookup returned scancode 0 and the key did nothing.
      'PgUp': 0x121,
      'PgDn': 0x122,
      'Home': 0x124,
      'End': 0x123,
    }.entries) {
      calls.clear();
      await tap(entry.key);
      expect(calls.map((c) => c.arguments).toList(), [
        {'vk': entry.value, 'down': true},
        {'vk': entry.value, 'down': false},
      ]);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RDP connecting shows a modern loading card with phase and spinner',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/44');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(44);
    await tester.pump();
    Future<void> event(Map<String, dynamic> state) async {
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('state', state)),
          (_) {});
      await tester.pump();
    }

    // Step 24, item 5: a compact card with a spinner, the current phase
    // text, and a quiet 'Ngắt' text button — not the old big black box.
    await event({'state': 'connecting', 'phase': 'creating'});
    expect(find.text('Đang tạo phiên…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await event({'state': 'connecting', 'phase': 'auth'});
    expect(find.text('Đang xác thực…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await event({'state': 'connecting'});
    expect(find.text('Đang kết nối…'), findsOneWidget);
    await tester.tap(find.text('Ngắt'));
    await tester.pump();
    expect(calls.last.method, 'disconnect');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stuck connecting state is cancelled after 30s (watchdog)',
      (tester) async {
    // Step 25, item 3: the spinner could sit forever if the native side
    // stayed 'connecting' (dropped session + auto-reconnect retries, or a
    // lost state event). The watchdog bounds it to 30s.
    const channel = MethodChannel('vn.aceremote.app/rdp/45');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(45);
    await tester.pump();
    Future<void> event(Map<String, dynamic> state) async {
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('state', state)),
          (_) {});
      await tester.pump();
    }

    await event({'state': 'connecting'});
    expect(find.text('Đang kết nối…'), findsOneWidget);
    // Still busy at 29s: no disconnect yet.
    await tester.pump(const Duration(seconds: 29));
    expect(calls.where((c) => c.method == 'disconnect'), isEmpty);
    expect(find.text('Đang kết nối…'), findsOneWidget);
    // At 30s the watchdog fires: it cancels the attempt and the spinner
    // is replaced by the form with a "Kết nối lại" button.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'disconnect'), isNotEmpty);
    expect(find.text('Đang kết nối…'), findsNothing);
    expect(find.textContaining('Kết nối quá lâu'), findsOneWidget);
    expect(find.text('Kết nối lại'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resuming from background re-syncs a stale connecting state',
      (tester) async {
    // Step 25, item 3: returning from recents re-queries the native
    // status, so a Dart state that went stale while the app was in the
    // background (lost state event) is corrected instead of showing
    // "Đang kết nối..." forever.
    const channel = MethodChannel('vn.aceremote.app/rdp/46');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      // The native side is idle (previous session gone); Dart still
      // thinks it is connecting.
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(46);
    await tester.pump();
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', {'state': 'connecting'})),
        (_) {});
    await tester.pump();
    expect(find.text('Đang kết nối…'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.value['state'], 'idle');
    expect(find.text('Đang kết nối…'), findsNothing);
    expect(find.text('Kết nối'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('repeated connecting events do not postpone the watchdog',
      (tester) async {
    // Step 26, item 1: FreeRDP's auto-reconnect loop fires a fresh
    // 'connecting' event per retry (OnReconnecting / OnPreConnect /
    // OnAuthenticate). Step 25 re-armed the 30s timer on every event,
    // so the watchdog never fired and the spinner sat forever. The
    // deadline is absolute now: it is set when the busy episode starts
    // and phase changes do not move it.
    const channel = MethodChannel('vn.aceremote.app/rdp/50');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(50);
    await tester.pump();
    Future<void> event(Map<String, dynamic> state) async {
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('state', state)),
          (_) {});
      await tester.pump();
    }

    await event({'state': 'connecting'});
    expect(find.text('Đang kết nối…'), findsOneWidget);
    // Fresh 'connecting' events every 10s, as the auto-reconnect loop
    // would send them. Each is a new Map, so the listener re-fires even
    // with identical content — exactly what used to re-arm the timer.
    // The watchdog must still fire at 30s absolute.
    await tester.pump(const Duration(seconds: 10));
    await event({'state': 'connecting'});
    await tester.pump(const Duration(seconds: 10));
    await event({'state': 'connecting'});
    await tester.pump(const Duration(seconds: 9));
    expect(calls.where((c) => c.method == 'disconnect'), isEmpty);
    expect(find.text('Đang kết nối…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'disconnect'), isNotEmpty);
    expect(find.text('Đang kết nối…'), findsNothing);
    expect(find.textContaining('Kết nối quá lâu'), findsOneWidget);
    expect(find.text('Kết nối lại'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resuming from background auto-reconnects a stuck session',
      (tester) async {
    // Step 26, item 1: the session dropped while the app was in the
    // background and FreeRDP's auto-reconnect loop is stuck on
    // 'connecting'. Returning from recents must kill the stale attempt
    // and start one fresh connect with the saved credentials — no tap
    // on "Kết nối lại" needed. Step 25 only re-queried the status.
    const channel = MethodChannel('vn.aceremote.app/rdp/51');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    var nativeState = 'idle';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'disconnect') nativeState = 'disconnected';
      if (call.method == 'status') return {'state': nativeState};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    FlutterSecureStorage.setMockInitialValues(
        {rdpUsernameKey: 'saved-user', rdpPasswordKey: 'saved-secret'});
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(51);
    await tester.pump();
    Future<void> event(Map<String, dynamic> state) async {
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('state', state)),
          (_) {});
      await tester.pump();
    }

    // A previous session connected (arms the resume auto-reconnect),
    // then dropped into a stuck 'connecting' loop in the background.
    await event({'state': 'connected'});
    nativeState = 'connecting';
    await event({'state': 'connecting'});
    expect(find.text('Đang kết nối…'), findsOneWidget);
    calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    // The stale attempt is killed first, then a fresh connect starts
    // with the saved credentials.
    expect(calls.where((c) => c.method == 'disconnect'), isNotEmpty);
    final connects = calls.where((c) => c.method == 'connect').toList();
    expect(connects, hasLength(1));
    expect(connects.single.arguments, {
      'host': '100.101.127.41',
      'port': 3389,
      'username': 'saved-user',
      'password': 'saved-secret',
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('F row matches number-key width and Delete is wider',
      (tester) async {
    // Step 25, item 5: the F row totals 16 units like the number row, so
    // F1-F12 are exactly as wide as the number keys; Delete (2.5 units)
    // is clearly wider than an F key.
    const channel = MethodChannel('vn.aceremote.app/rdp/47');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    await tester.pumpAndSettle();
    Size keySize(String label) => tester.getSize(find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first);
    expect(keySize('F1').width, closeTo(keySize('1').width, 1.0));
    expect(keySize('F12').width, closeTo(keySize('0').width, 1.0));
    expect(keySize('Del').width, greaterThan(keySize('F1').width * 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keyboard keeps sane key sizes on folded and unfolded screens',
      (tester) async {
    // Step 25, item 4: on the Fold6 folded screen (narrow, tall) the rows
    // used to stretch so keys were tall rectangles; on the unfolded screen
    // they were oversized. Row height now follows the key width and is
    // clamped, so keys stay proportionate at both sizes with no overflow.
    const channel = MethodChannel('vn.aceremote.app/rdp/48');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    Size keySize(String label) => tester.getSize(find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first);
    for (final size in [
      const Size(378, 800), // Fold6 folded (narrow, tall)
      const Size(800, 800), // Fold6 unfolded (wide)
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      await tester.pumpAndSettle();
      final key = keySize('A');
      // Keys are never stretched tall and never tiny: row height is
      // clamped to the 44-64dp band, and the key itself is 4dp shorter
      // (2dp padding on each side).
      expect(key.height, greaterThanOrEqualTo(40.0));
      expect(key.height, lessThanOrEqualTo(60.0));
      // All rows share the same height, and ↑ still equals ↓.
      expect(keySize('↑').height, closeTo(keySize('↓').height, 1.0));
      expect(keySize('F1').width, closeTo(keySize('1').width, 1.0));
      // Step 26, item 4: on the narrow (folded) screen the wide keys
      // shrink so the letter/number keys get wider. Tab drops to 1.0
      // units (same as a letter), Shift to 1.5, Backspace to 1.5; on
      // the wide screen the step 24/25 units stay (Tab 1.5, Shift
      // 2.25, Backspace 2.0). ↑ still equals ↓ in width at both sizes.
      // Widths below are Container widths; each key also has 2dp
      // padding on each side, so add 4 back to compare flex shares.
      double share(String label) => keySize(label).width + 4;
      final narrow = size.width < 600;
      expect(share('Tab'),
          closeTo(share('A') * (narrow ? 1.0 : 1.5), 1.0));
      // 'Z' shares Shift's row, so the ratio is exact (rows 3 and 4
      // have different totals: 16.0 vs 16.25 wide, 15.0 vs 15.0 narrow).
      expect(share('Shift'),
          closeTo(share('Z') * (narrow ? 1.5 : 2.25), 1.0));
      expect(share('Backspace'),
          closeTo(share('1') * (narrow ? 1.5 : 2.0), 1.0));
      expect(keySize('↑').width, closeTo(keySize('↓').width, 1.0));
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'step 36: clickKeys config hides Left/Right keys, Space grows (RDP)',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/35');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    Future<void> pumpWith(ClickKeys clickKeys) async {
      await tester.pumpWidget(MaterialApp(
          home: RemotePage(
              agent: agent,
              pollMs: () => 1000,
              rdpMode: true,
              rdpConnection: RdpConnectionStore.defaultConnection
                  .copyWith(clickKeys: clickKeys))));
      await tester.pump();
    }

    List<String?> rowLabels() => tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey('keyboard-row-5')),
            matching: find.byType(Text)))
        .map((w) => w.data)
        .toList();
    Size keySize(String label) => tester.getSize(find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first);
    // Widths below are Container widths; each key also has 2dp padding on
    // each side, so add 4 back to compare flex shares.
    double share(String label) => keySize(label).width + 4;
    // showBoth (default): the two click keys are there, Space is its
    // normal width (4.5 units = 4.5x a letter key; ratio, not absolute px,
    // so pixel rounding on flex shares does not matter).
    await pumpWith(ClickKeys.showBoth);
    expect(rowLabels(), [
      'Ctrl',
      'Win',
      'Alt',
      'Left',
      'Space',
      'Right',
      'Alt',
      'Ctrl',
      '←',
      '↓',
      '→'
    ]);
    expect(share('Space') / share('A'), closeTo(4.5, 0.1));
    // hideRight: Left stays, Right disappears, Space takes Right's width
    // (4.5 + 1.25 = 5.75 units).
    await pumpWith(ClickKeys.hideRight);
    expect(rowLabels(), [
      'Ctrl',
      'Win',
      'Alt',
      'Left',
      'Space',
      'Alt',
      'Ctrl',
      '←',
      '↓',
      '→'
    ]);
    expect(find.text('Right'), findsNothing);
    expect(share('Space') / share('A'), closeTo(5.75, 0.15));
    // hideBoth: both keys disappear and Space takes their width
    // (4.5 + 2 x 1.25 = 7.0 units); every other key keeps its size.
    await pumpWith(ClickKeys.hideBoth);
    expect(rowLabels(),
        ['Ctrl', 'Win', 'Alt', 'Space', 'Alt', 'Ctrl', '←', '↓', '→']);
    expect(find.text('Left'), findsNothing);
    expect(find.text('Right'), findsNothing);
    expect(share('Space') / share('A'), closeTo(7.0, 0.15));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('step 36: agent mode always shows Left/Right keys',
      (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(
            agent: agent,
            pollMs: () => 1000,
            rdpMode: false,
            rdpConnection: RdpConnectionStore.defaultConnection
                .copyWith(clickKeys: ClickKeys.hideBoth))));
    await tester.pump();
    // The click-keys setting only applies in RDP mode; agent mode keeps
    // both keys even when the connection says hideBoth.
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('step 37: trackpad area shows only unfolded with config on',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/38');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    Future<void> pumpWith(Size surface, bool area) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(MaterialApp(
          home: RemotePage(
              agent: agent,
              pollMs: () => 1000,
              rdpMode: true,
              rdpConnection: RdpConnectionStore.defaultConnection
                  .copyWith(trackpadArea: area))));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    Size keySize(String label) => tester.getSize(find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first);
    // Unfolded + on: the area shows below the keys, and the key rows
    // shrink (row 56.6 -> 41.5 with the step 38 palm-rest gap, so an 'A'
    // key is 37.5 tall, not 52.6). The area stays full width, exactly as
    // wide as the keyboard rows.
    await pumpWith(const Size(800, 800), true);
    expect(find.byKey(const ValueKey('trackpad-area')), findsOneWidget);
    expect(keySize('A').height, closeTo(37.5, 1.5));
    expect(tester.getSize(find.byKey(const ValueKey('trackpad-area'))).width,
        closeTo(792.0, 1.0));
    // Step 38: rounded like a laptop trackpad, and blank (no icon).
    // Step 39: the visible pad is the gray rounded rectangle in the
    // middle, like the photo An sent — 60% of the strip width, centered,
    // clearly gray (#3a3b40) against the dark deck. The touch zone is
    // still the whole strip (792 wide).
    // Step 40: corner radius 16 -> 8 — on the short pad, 16 looked like
    // a pill; a real laptop trackpad is only gently rounded. Pad width
    // 60% -> 40% of the strip (MacBook-like): at 60% it looked like a
    // wide bar, not a laptop trackpad.
    // Step 44: 40% -> 35% — An picked 35% after seeing the 40%-vs-35%
    // comparison (Dell XPS proportion, a touch more balanced).
    final padBox = tester.widget<Container>(
        find.byKey(const ValueKey('trackpad-pad')));
    expect((padBox.decoration as BoxDecoration?)?.borderRadius,
        BorderRadius.circular(8));
    // Step 42: the pad has a sheen gradient + soft drop shadow like the
    // photo's trackpad, not a flat solid gray.
    expect((padBox.decoration as BoxDecoration?)?.color, isNull);
    final padGradient =
        (padBox.decoration as BoxDecoration?)?.gradient as LinearGradient?;
    expect(padGradient?.colors,
        [const Color(0xff48494f), const Color(0xff343539)]);
    expect((padBox.decoration as BoxDecoration?)?.boxShadow?.length, 1);
    expect(tester.getSize(find.byKey(const ValueKey('trackpad-pad'))).width,
        closeTo(277.2, 2.0));
    expect(tester.getTopLeft(find.byKey(const ValueKey('trackpad-pad'))).dx,
        closeTo(261.4, 2.0));
    expect(find.byIcon(Icons.touch_app_outlined), findsNothing);
    // Unfolded + off: no area, full-height keys.
    await pumpWith(const Size(800, 800), false);
    expect(find.byKey(const ValueKey('trackpad-area')), findsNothing);
    expect(keySize('A').height, closeTo(52.6, 1.0));
    // Folded + on: the area stays hidden, keys full height.
    await pumpWith(const Size(378, 800), true);
    expect(find.byKey(const ValueKey('trackpad-area')), findsNothing);
    expect(keySize('A').height, closeTo(40.0, 1.0));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('step 37: tapping the area left-clicks, dragging moves',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/39');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(
            agent: agent,
            pollMs: () => 1000,
            rdpMode: true,
            rdpConnection: RdpConnectionStore.defaultConnection
                .copyWith(trackpadArea: true))));
    await tester.pump();
    await tester.pumpAndSettle();
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(39);
    calls.clear();
    // A plain tap on the area is a left click at the cursor.
    await tester.tap(find.byKey(const ValueKey('trackpad-area')));
    await tester.pump();
    expect(calls,
        contains(isMethodCall('click', arguments: {'button': 'left'})));
    // A drag on the area moves the cursor relatively.
    calls.clear();
    await tester.drag(find.byKey(const ValueKey('trackpad-area')),
        const Offset(60, 0));
    await tester.pump();
    expect(calls.any((c) => c.method == 'moveRelative'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('step 43: keys have a keycap sheen gradient and drop shadow',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/40');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    await tester.pump();
    await tester.pumpAndSettle();
    final keyBox = tester.widget<Container>(find
        .ancestor(of: find.text('A'), matching: find.byType(Container))
        .first);
    final decoration = keyBox.decoration as BoxDecoration?;
    // Real keycaps: a soft sheen, lighter on top, with a gentle drop
    // shadow lifting the key off the deck — not a flat solid color.
    expect((decoration?.gradient as LinearGradient?)?.colors,
        [const Color(0xff3a3d44), const Color(0xff2b2e34)]);
    expect(decoration?.boxShadow?.length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('step 34: RdpController mouseMove/mouseButton call the channel',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/36');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = RdpController();
    await controller.attach(36);
    calls.clear();
    await controller.sendMouseMove(const Offset(400, 100));
    await controller.sendMouseButton(const Offset(400, 100), 'right', true);
    await controller.sendMouseButton(const Offset(400, 100), 'right', false);
    expect(calls.map((c) => c.method),
        ['mouseMove', 'mouseButton', 'mouseButton']);
    expect(calls[0].arguments, {'x': 400.0, 'y': 100.0});
    expect(calls[1].arguments,
        {'x': 400.0, 'y': 100.0, 'button': 'right', 'down': true});
    expect(calls[2].arguments,
        {'x': 400.0, 'y': 100.0, 'button': 'right', 'down': false});
    controller.dispose();
  });

  testWidgets(
      'step 34: mouse hover/click over the remote screen drives the PC cursor',
      (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/37');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    // Pin dpr to 1.0 so logical px == surface px in the expectations below
    // (the test binding defaults to 3.0).
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = Agent(
        baseUrl: defaultBaseUrl,
        client: MockClient((_) async {
          throw StateError('RDP must not contact agent');
        }));
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RemotePage(agent: agent, pollMs: () => 1000, rdpMode: true)));
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(37);
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', {'state': 'connected'})),
        (_) {});
    await tester.pump();
    expect(controller.isConnected, isTrue);
    calls.clear();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // Hover over the remote screen: absolute move (dpr is 1.0 in tests,
    // so logical px == surface px).
    binding.handlePointerEvent(const PointerHoverEvent(
      position: Offset(400, 100),
      kind: PointerDeviceKind.mouse,
    ));
    await tester.pump();
    expect(calls.map((c) => c.method), ['mouseMove']);
    expect(calls.single.arguments, {'x': 400.0, 'y': 100.0});
    calls.clear();
    // Left button down then up: press + release, no touch tap.
    binding.handlePointerEvent(const PointerDownEvent(
      position: Offset(400, 100),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    ));
    await tester.pump();
    expect(calls.map((c) => c.method), ['mouseButton']);
    expect(calls.single.arguments,
        {'x': 400.0, 'y': 100.0, 'button': 'left', 'down': true});
    calls.clear();
    binding.handlePointerEvent(const PointerUpEvent(
      position: Offset(400, 100),
      kind: PointerDeviceKind.mouse,
      buttons: 0,
    ));
    await tester.pump();
    expect(calls.map((c) => c.method), ['mouseButton']);
    expect(calls.single.arguments,
        {'x': 400.0, 'y': 100.0, 'button': 'left', 'down': false});
    calls.clear();
    // Wheel: one notch per event.
    binding.handlePointerEvent(const PointerScrollEvent(
      position: Offset(400, 100),
      kind: PointerDeviceKind.mouse,
      scrollDelta: Offset(0, 120),
    ));
    await tester.pump();
    expect(calls.map((c) => c.method), ['scroll']);
    expect(calls.single.arguments, {'down': true});
    await tester.pumpWidget(const SizedBox());
  });

}
