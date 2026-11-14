import 'dart:convert';

import 'package:ace_remote/agent.dart';
import 'package:ace_remote/main.dart';
import 'package:ace_remote/rdp_connections.dart';
import 'package:ace_remote/rdp_credentials.dart';
import 'package:ace_remote/rdp_surface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Step 31 tests write straight to the underlying prefs store (the same
// thing Kotlin does) to simulate an external change. The platform
// interface is a transitive dependency of shared_preferences; this is a
// test-only use, so the version in pubspec.yaml is left untouched.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Scrolls the connection editor's list until the save button is built and
/// taps it. The button sits below the ListView's cache extent on a tall
/// page, so ensureVisible cannot find it before scrolling (and
/// scrollUntilVisible cannot pick the list's Scrollable out of the
/// TextFields' own Scrollables).
Future<void> _saveFromEditor(WidgetTester tester) async {
  for (var i = 0; i < 10 && find.text('Lưu').evaluate().isEmpty; i++) {
    await tester.drag(find.byKey(const ValueKey('connection-editor-list')),
        const Offset(0, -300));
    await tester.pump();
  }
  // The button can be built (ListView cache extent) while still below the
  // viewport, so a tap would land off-screen. Scroll it fully into view
  // first — the editor grew again in step 37.
  await tester.ensureVisible(find.text('Lưu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lưu'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('load seeds the default ace connection on first run', () async {
    final connections = await RdpConnectionStore().load();
    expect(connections, hasLength(1));
    expect(connections.first.id, 'ace');
    expect(connections.first.name, 'ace — Windows');
    expect(connections.first.host, '100.101.127.41');
    expect(connections.first.port, 3389);
  });

  test('seed carries over the single credentials saved by step 21', () async {
    await storage.write(
        key: rdpUsernameKey, value: 'steve', aOptions: rdpStorageOptions);
    await storage.write(
        key: rdpPasswordKey, value: 'pw123', aOptions: rdpStorageOptions);
    final store = RdpConnectionStore();
    final connections = await store.load();
    expect(connections.first.username, 'steve');
    expect(await store.passwordFor('ace'), 'pw123');
  });

  test('add stores the record in prefs and the password only in secure storage',
      () async {
    final store = RdpConnectionStore();
    final added = await store.add(
        name: 'PC test',
        host: '10.0.0.5',
        port: 3389,
        username: 'steve',
        password: 's3cret');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(RdpConnectionStore.listKey)!;
    expect(raw, contains('PC test'));
    expect(raw, isNot(contains('s3cret')));
    expect(raw, isNot(contains('steve')));
    expect(await store.passwordFor(added.id), 's3cret');
    expect(await store.usernameFor(added.id), 'steve');
    final all = await store.load();
    expect(all.map((c) => c.name), containsAll(['ace — Windows', 'PC test']));
    expect(all.singleWhere((c) => c.id == added.id).username, 'steve');
  });

  test('update changes the record and password', () async {
    final store = RdpConnectionStore();
    final added = await store.add(
        name: 'PC test',
        host: '10.0.0.5',
        port: 3389,
        username: 'steve',
        password: 's3cret');
    await store.update(added.copyWith(name: 'PC doi ten', host: '10.0.0.6'),
        password: 'pw-moi');
    final all = await store.load();
    final updated = all.singleWhere((c) => c.id == added.id);
    expect(updated.name, 'PC doi ten');
    expect(updated.host, '10.0.0.6');
    expect(await store.passwordFor(added.id), 'pw-moi');
  });

  test('remove deletes the record and its secure keys', () async {
    final store = RdpConnectionStore();
    final added = await store.add(
        name: 'PC test',
        host: '10.0.0.5',
        port: 3389,
        username: 'steve',
        password: 's3cret');
    await store.remove(added.id);
    final all = await store.load();
    expect(all.map((c) => c.id), isNot(contains(added.id)));
    expect(await store.passwordFor(added.id), '');
    expect(await store.usernameFor(added.id), '');
  });

  test('saveCredentials writes the per-connection keys', () async {
    final store = RdpConnectionStore();
    await store.saveCredentials('ace', username: 'steve', password: 'pw123');
    expect(await store.usernameFor('ace'), 'steve');
    expect(await store.passwordFor('ace'), 'pw123');
  });

  test('trackpad, keyboard and favorite settings round-trip; favorites sort first',
      () async {
    final store = RdpConnectionStore();
    final plain = await store.add(
        name: 'PC thuong', host: '10.0.0.5', port: 3389);
    final starred = await store.add(
        name: 'PC yeu thich',
        host: '10.0.0.6',
        port: 3390,
        trackpadMode: true,
        keyboardVisible: false,
        favorite: true);
    var all = await store.load();
    expect(all.first.id, starred.id);
    expect(all.first.trackpadMode, isTrue);
    expect(all.first.keyboardVisible, isFalse);
    expect(all.first.favorite, isTrue);
    expect(all.last.id, plain.id);
    // Old records without the new keys get the defaults.
    await store.update(plain.copyWith(favorite: true));
    all = await store.load();
    expect(all.map((c) => c.id).toList(), [plain.id, starred.id, 'ace']);
    expect(all.firstWhere((c) => c.id == plain.id).trackpadMode, isFalse);
    expect(all.firstWhere((c) => c.id == plain.id).keyboardVisible, isTrue);
  });

  test('step 36: clickKeys round-trips; old records default to showBoth',
      () async {
    final store = RdpConnectionStore();
    final hidden = await store.add(
        name: 'PC an phim',
        host: '10.0.0.7',
        port: 3389,
        clickKeys: ClickKeys.hideBoth);
    var all = await store.load();
    expect(
        all.firstWhere((c) => c.id == hidden.id).clickKeys,
        ClickKeys.hideBoth);
    // A record written before step 36 (no 'clickKeys' key) and one with an
    // unknown value both fall back to showBoth.
    final raw = <String, dynamic>{
      'id': 'old',
      'name': 'old',
      'host': '10.0.0.1',
      'port': 3389,
    };
    expect(RdpConnection.fromJson(raw).clickKeys, ClickKeys.showBoth);
    raw['clickKeys'] = 'nope';
    expect(RdpConnection.fromJson(raw).clickKeys, ClickKeys.showBoth);
    // toJson/fromJson keeps every level.
    for (final level in ClickKeys.values) {
      final roundTripped = RdpConnection.fromJson(
          RdpConnectionStore.defaultConnection
              .copyWith(clickKeys: level)
              .toJson());
      expect(roundTripped.clickKeys, level);
    }
    // Step 37: trackpadArea round-trips and defaults to false.
    final withArea = await store.add(
        name: 'PC trackpad', host: '10.0.0.8', port: 3389, trackpadArea: true);
    all = await store.load();
    expect(all.firstWhere((c) => c.id == withArea.id).trackpadArea, isTrue);
    expect(RdpConnection.fromJson(raw).trackpadArea, isFalse);
  });

  test('step 48: trackpadSensitivity round-trips; old records default to 1.5',
      () async {
    final store = RdpConnectionStore();
    final fast = await store.add(
        name: 'PC nhanh',
        host: '10.0.0.9',
        port: 3389,
        trackpadSensitivity: 2.5);
    final all = await store.load();
    expect(all.firstWhere((c) => c.id == fast.id).trackpadSensitivity, 2.5);
    // A record written before step 48 (no key) falls back to 1.5.
    final raw = <String, dynamic>{
      'id': 'old',
      'name': 'old',
      'host': '10.0.0.1',
      'port': 3389,
    };
    expect(RdpConnection.fromJson(raw).trackpadSensitivity, 1.5);
    final roundTripped = RdpConnection.fromJson(RdpConnectionStore
        .defaultConnection
        .copyWith(trackpadSensitivity: 0.75)
        .toJson());
    expect(roundTripped.trackpadSensitivity, 0.75);
  });

  test('load sees values changed on disk after reload, without restart',
      () async {
    // Step 31: the native widget writes straight to the prefs file
    // (Kotlin), so the app's in-RAM SharedPreferences cache is stale
    // until reload() — the same lesson as Thuoc Vui v1.2.13/v1.2.14.
    final store = RdpConnectionStore();
    await store.add(
        name: 'PC', host: '10.0.0.5', port: 3389, trackpadMode: false);
    var all = await store.load();
    expect(all.firstWhere((c) => c.name == 'PC').trackpadMode, isFalse);
    // Simulate the widget flipping trackpad on disk: write straight to
    // the underlying store, bypassing the Dart-side cache — exactly what
    // Kotlin does when it edits FlutterSharedPreferences. (Calling
    // setMockInitialValues here would NOT simulate it: it nullifies the
    // cached singleton, so the next getInstance() would see the new
    // values at once, without any reload.)
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(RdpConnectionStore.listKey)!;
    final decoded = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    decoded.firstWhere((m) => m['name'] == 'PC')['trackpad'] = true;
    await SharedPreferencesStorePlatform.instance.setValue(
        'String',
        'flutter.${RdpConnectionStore.listKey}',
        jsonEncode(decoded));
    // The cached instance still sees the old value.
    all = await store.load();
    expect(all.firstWhere((c) => c.name == 'PC').trackpadMode, isFalse);
    // After reload() the new value is visible — no restart needed.
    await prefs.reload();
    all = await store.load();
    expect(all.firstWhere((c) => c.name == 'PC').trackpadMode, isTrue);
  });

  testWidgets('Home reloads its list when the app resumes after a widget tap',
      (tester) async {
    // Step 31: Home listens to the resume tick bumped by _AceAppState on
    // resume; _reload() re-reads prefs from disk first, so a connection
    // changed on the widget while the app was away shows up at once.
    final resumeTick = ValueNotifier<int>(0);
    addTearDown(resumeTick.dispose);
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox(),
            resumeTick: resumeTick)));
    await tester.pumpAndSettle();
    expect(find.text('ace — Windows'), findsOneWidget);
    expect(find.text('PC moi'), findsNothing);
    // The widget adds a connection on disk while the app is away: write
    // straight to the underlying store, bypassing the Dart-side cache —
    // exactly what Kotlin does. (setMockInitialValues would NOT simulate
    // it: it nullifies the cached singleton, so the next getInstance()
    // would see the new values at once, with or without reload().)
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(RdpConnectionStore.listKey)!;
    final decoded = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    decoded.add({
      'id': 'pc-moi',
      'name': 'PC moi',
      'host': '10.0.0.9',
      'port': 3390,
      'trackpad': true,
      'keyboard': true,
      'favorite': false,
    });
    await SharedPreferencesStorePlatform.instance.setValue(
        'String',
        'flutter.${RdpConnectionStore.listKey}',
        jsonEncode(decoded));
    // Before the resume tick, Home still shows the old list.
    await tester.pump();
    expect(find.text('PC moi'), findsNothing);
    // The app comes back: the tick fires, Home reloads from disk.
    resumeTick.value++;
    await tester.pumpAndSettle();
    expect(find.text('PC moi'), findsOneWidget);
    expect(find.text('10.0.0.9:3390'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Home lists saved connections; tapping one connects with its saved credentials',
      (tester) async {
    // Step 21 already saved a user/pass: the seeded ace connection inherits them.
    await storage.write(
        key: rdpUsernameKey, value: 'steve', aOptions: rdpStorageOptions);
    await storage.write(
        key: rdpPasswordKey, value: 'pw123', aOptions: rdpStorageOptions);
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
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    expect(find.text('Kết nối đã lưu'), findsOneWidget);
    expect(find.text('ace — Windows'), findsOneWidget);
    expect(find.text('steve'), findsOneWidget);
    expect(find.text('100.101.127.41:3389'), findsOneWidget);
    await tester.tap(find.text('ace — Windows'));
    // The pushed route needs two frames to appear in the tree.
    await tester.pump();
    await tester.pump();
    // Attach the controller (as the platform view would) so connect() can send.
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(0);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final connectCall = calls.singleWhere((c) => c.method == 'connect');
    expect(connectCall.arguments, {
      'host': '100.101.127.41',
      'port': 3389,
      'username': 'steve',
      'password': 'pw123',
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('add connection page saves a new card with its settings', (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    expect(find.text('ace — Windows'), findsOneWidget);
    await tester.tap(find.byTooltip('Thêm kết nối'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm kết nối'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('connection-name')), 'PC moi');
    await tester.enterText(
        find.byKey(const ValueKey('connection-host')), '10.0.0.9');
    await tester.enterText(
        find.byKey(const ValueKey('connection-port')), '3390');
    await tester.enterText(
        find.byKey(const ValueKey('connection-username')), 'admin');
    await tester.enterText(
        find.byKey(const ValueKey('connection-password')), 'pw-moi');
    // Turn on trackpad mode for the new connection.
    await tester.ensureVisible(find.text('Chế độ Trackpad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chế độ Trackpad'));
    await tester.pump();
    // Pick the click-keys level for the new connection (step 36).
    await tester.ensureVisible(find.text('Ẩn cả 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ẩn cả 2'));
    await tester.pump();
    await _saveFromEditor(tester);
    expect(find.text('PC moi'), findsOneWidget);
    expect(find.text('10.0.0.9:3390'), findsOneWidget);
    expect(find.text('admin'), findsOneWidget);
    // The password went to secure storage, not into the prefs JSON.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(RdpConnectionStore.listKey),
        isNot(contains('pw-moi')));
    final store = RdpConnectionStore();
    final all = await store.load();
    final added = all.singleWhere((c) => c.name == 'PC moi');
    expect(await store.passwordFor(added.id), 'pw-moi');
    expect(added.trackpadMode, isTrue);
    expect(added.keyboardVisible, isTrue);
    expect(added.clickKeys, ClickKeys.hideBoth);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long-press menu edits a connection and saves its settings', (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('ace — Windows'));
    await tester.pumpAndSettle();
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Favorite'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Sửa kết nối'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('connection-name')), 'ace doi ten');
    await tester.ensureVisible(find.text('Chế độ Trackpad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chế độ Trackpad'));
    await tester.pump();
    await _saveFromEditor(tester);
    expect(find.text('ace doi ten'), findsOneWidget);
    expect(find.text('ace — Windows'), findsNothing);
    final store = RdpConnectionStore();
    final all = await store.load();
    expect(all.singleWhere((c) => c.name == 'ace doi ten').trackpadMode,
        isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('step 41: enabling the trackpad defaults click keys to hidden',
      (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('ace — Windows'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    // Turn the trackpad area on: the click-keys level follows to hide
    // both by default.
    await tester.ensureVisible(find.text('Vùng trackpad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vùng trackpad'));
    await tester.pump();
    await _saveFromEditor(tester);
    final store = RdpConnectionStore();
    final all = await store.load();
    expect(all.singleWhere((c) => c.name == 'ace — Windows').trackpadArea,
        isTrue);
    expect(all.singleWhere((c) => c.name == 'ace — Windows').clickKeys,
        ClickKeys.hideBoth);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('step 48: trackpad sensitivity slider saves per connection',
      (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('ace — Windows'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    // Default 1.50x shown next to the slider. The slider sits below the
    // ListView's cache extent, so scroll the list until its title is built
    // (the key alone finds nothing until the item exists).
    for (var i = 0;
        i < 10 && find.text('Độ nhạy trackpad').evaluate().isEmpty;
        i++) {
      await tester.drag(
          find.byKey(const ValueKey('connection-editor-list')),
          const Offset(0, -300));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Độ nhạy trackpad'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const ValueKey('trackpad-sensitivity')));
    await tester.pumpAndSettle();
    expect(find.text('1.50×'), findsOneWidget);
    // Drag the slider all the way right: sensitivity goes to the 3.0x max.
    await tester.drag(
        find.byKey(const ValueKey('trackpad-sensitivity')),
        const Offset(500, 0));
    await tester.pump();
    expect(find.text('3.00×'), findsWidgets);
    await _saveFromEditor(tester);
    final store = RdpConnectionStore();
    final all = await store.load();
    expect(all.singleWhere((c) => c.name == 'ace — Windows').trackpadSensitivity,
        3.0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('step 41: the trackpad default can be overridden',
      (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('ace — Windows'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Vùng trackpad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vùng trackpad'));
    await tester.pump();
    // The user can still pick "Hiện cả 2" afterwards.
    await tester.ensureVisible(find.text('Hiện cả 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hiện cả 2'));
    await tester.pump();
    await _saveFromEditor(tester);
    final store = RdpConnectionStore();
    final all = await store.load();
    final edited = all.singleWhere((c) => c.name == 'ace — Windows');
    expect(edited.trackpadArea, isTrue);
    expect(edited.clickKeys, ClickKeys.showBoth);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long-press menu deletes a connection after confirmation',
      (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    expect(find.text('ace — Windows'), findsOneWidget);
    await tester.longPress(find.text('ace — Windows'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa'));
    await tester.pumpAndSettle();
    expect(find.text('ace — Windows'), findsNothing);
    expect(find.textContaining('Chưa có kết nối nào'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long-press menu favorites a connection and pins it first', (tester) async {
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    final store = RdpConnectionStore();
    await store.add(name: 'PC thu hai', host: '10.0.0.5', port: 3389);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('PC thu hai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorite'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(
        tester.getTopLeft(find.text('PC thu hai')).dy,
        lessThan(tester.getTopLeft(find.text('ace — Windows')).dy));
    // Unfavorite from the menu: the label flips and the star goes away.
    await tester.longPress(find.text('PC thu hai'));
    await tester.pumpAndSettle();
    expect(find.text('Bỏ yêu thích'), findsOneWidget);
    await tester.tap(find.text('Bỏ yêu thích'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Back from the remote page disconnects and returns to Home', (tester) async {
    await storage.write(
        key: rdpUsernameKey, value: 'steve', aOptions: rdpStorageOptions);
    await storage.write(
        key: rdpPasswordKey, value: 'pw123', aOptions: rdpStorageOptions);
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
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ace — Windows'));
    await tester.pump();
    await tester.pump();
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    await controller.attach(0);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(calls.map((c) => c.method), contains('connect'));
    calls.clear();
    // System back (no AppBar back button on the remote page, so pageBack()
    // cannot be used): the PopScope pops the route and disconnects first.
    final popped = await tester.binding.handlePopRoute();
    expect(popped, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Kết nối đã lưu'), findsOneWidget);
    expect(find.text('ace — Windows'), findsOneWidget);
    expect(calls.map((c) => c.method), contains('disconnect'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening a connection applies its trackpad and keyboard settings', (tester) async {
    const channel = MethodChannel('vn.aceremote.app/rdp/0');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'idle'};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final store = RdpConnectionStore();
    await store.add(
        name: 'PC trackpad',
        host: '10.0.0.5',
        port: 3389,
        username: 'steve',
        password: 'pw123',
        trackpadMode: true,
        keyboardVisible: false);
    final agent = Agent(baseUrl: defaultBaseUrl, mock: true);
    addTearDown(agent.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Home(
            agent: agent,
            pollMs: () => 1000,
            settings: () => const SizedBox())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PC trackpad'));
    await tester.pump();
    await tester.pump();
    final controller =
        tester.widget<RdpSurface>(find.byType(RdpSurface)).controller!;
    expect(controller.trackpadMode.value, isTrue);
    expect(controller.keyboardVisible.value, isFalse);
    // The keyboard half is hidden: the remote screen fills the page.
    expect(find.byKey(const ValueKey('remote-half')), findsOneWidget);
    expect(find.byKey(const ValueKey('keyboard-half')), findsNothing);
    // Let the auto-connect's 400ms layout delay elapse before disposing,
    // or the test ends with a timer still pending.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });
}
