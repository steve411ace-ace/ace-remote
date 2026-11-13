import 'package:ace_remote/agent.dart';
import 'package:ace_remote/main.dart';
import 'package:ace_remote/rdp_surface.dart';
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
    expect(find.text('Đã kết nối'), findsOneWidget);
    expect(find.text('Kết nối lại'), findsNothing);
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

  testWidgets('RDP waiting page keeps equal halves and sends no agent traffic',
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
      expect(remote.height, size.height / 4);
      expect(keyboard.height, remote.height);
      expect(keyboard.top, remote.bottom);
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
    expect(find.text('Đã kết nối'), findsOneWidget);
    expect(find.byKey(const ValueKey('rdp-password')), findsNothing);
    await tester.tap(find.text('Ngắt kết nối'));
    await tester.pump();
    expect(calls.last.method, 'disconnect');
    await event({'state': 'failed', 'error': 'Test failure', 'authAttempted': true});
    expect(find.text('Test failure'), findsOneWidget);
    expect(find.text('Kết nối lại'), findsOneWidget);
    expect(find.text('Đã đi qua callback xác thực; chưa xác định nguyên nhân.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('rdp-password'))).controller!.text, isEmpty);
    await event({'state': 'failed', 'authAttempted': false});
    expect(find.text('Chưa đi qua callback xác thực; chưa xác định nguyên nhân.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('connected header auto-hides, reveals, and toggles mode/keyboard', (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/23');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'status' ? {'state': 'idle'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = RdpController();
    await controller.attach(23);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RdpConnectionPane(controller: controller))));
    await tester.pumpAndSettle();
    calls.clear();
    controller.value = {'state': 'connected'};
    await tester.pump();
    expect(find.text('Đã kết nối'), findsOneWidget);
    expect(find.text('Ngắt kết nối'), findsOneWidget);
    expect(find.text('Trackpad'), findsOneWidget);
    expect(find.text('Ẩn bàn phím'), findsOneWidget);
    // Toggle to trackpad mode: sends 'mode' to native and relabels the button.
    await tester.tap(find.text('Trackpad'));
    await tester.pump();
    expect(controller.trackpadMode.value, isTrue);
    expect(find.text('Chạm'), findsOneWidget);
    expect(calls.map((c) => c.method), contains('mode'));
    expect(calls.lastWhere((c) => c.method == 'mode').arguments, {'trackpad': true});
    // The header stays for 3s after the tap, then auto-hides.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Đã kết nối'), findsNothing);
    expect(find.text('Ngắt kết nối'), findsNothing);
    expect(find.byTooltip('Hiện điều khiển'), findsOneWidget);
    // Reveal button brings the header back.
    await tester.tap(find.byTooltip('Hiện điều khiển'));
    await tester.pump();
    expect(find.text('Đã kết nối'), findsOneWidget);
    // Hide the keyboard: the toggle relabels and the controller flips.
    await tester.tap(find.text('Ẩn bàn phím'));
    await tester.pump();
    expect(controller.keyboardVisible.value, isFalse);
    expect(find.text('Hiện bàn phím'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('RDP trackpad mode swaps keyboard for a trackpad surface', (tester) async {
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
    expect(find.text('Esc'), findsOneWidget);
    expect(find.byKey(const ValueKey('rdp-trackpad')), findsNothing);
    calls.clear();
    await controller.setTrackpadMode(true);
    await tester.pump();
    expect(find.text('Esc'), findsNothing);
    expect(find.byKey(const ValueKey('rdp-trackpad')), findsOneWidget);
    expect(calls.map((c) => c.method), contains('mode'));
    expect(calls.lastWhere((c) => c.method == 'mode').arguments,
        {'trackpad': true});
    // Drag on the trackpad sends relative moves.
    calls.clear();
    await tester.drag(find.byKey(const ValueKey('rdp-trackpad')),
        const Offset(60, 0));
    await tester.pump();
    expect(calls.map((c) => c.method), contains('moveRelative'));
    final move = calls.firstWhere((c) => c.method == 'moveRelative');
    expect((move.arguments as Map)['dx'], greaterThan(0));
    // Quick tap clicks left at the cursor.
    calls.clear();
    await tester.tap(find.byKey(const ValueKey('rdp-trackpad')));
    await tester.pump();
    expect(calls.map((c) => c.method), contains('click'));
    expect(calls.lastWhere((c) => c.method == 'click').arguments,
        {'button': 'left'});
    // Two-finger tap clicks right.
    calls.clear();
    final center =
        tester.getCenter(find.byKey(const ValueKey('rdp-trackpad')));
    final first = await tester.startGesture(center);
    final second = await tester.startGesture(center + const Offset(20, 0));
    await first.up();
    await second.up();
    await tester.pump();
    expect(calls.map((c) => c.method), contains('click'));
    expect(calls.lastWhere((c) => c.method == 'click').arguments,
        {'button': 'right'});
    // Back to touch mode restores the keyboard.
    await controller.setTrackpadMode(false);
    await tester.pump();
    expect(find.text('Esc'), findsOneWidget);
    expect(find.byKey(const ValueKey('rdp-trackpad')), findsNothing);
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
    expect(remote.height, 300);
    expect(keyboard.height, remote.height);
    controller.keyboardVisible.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey('keyboard-half')), findsNothing);
    remote = tester.getRect(find.byKey(const ValueKey('remote-half')));
    expect(remote.height, 600);
    controller.keyboardVisible.value = true;
    await tester.pump();
    remote = tester.getRect(find.byKey(const ValueKey('remote-half')));
    keyboard = tester.getRect(find.byKey(const ValueKey('keyboard-half')));
    expect(remote.height, 300);
    expect(keyboard.height, remote.height);
    await tester.pumpWidget(const SizedBox());
  });

}
