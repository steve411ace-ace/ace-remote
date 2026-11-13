// Step 27: tests for the home-screen widget Dart logic.
//
// The native side (AppWidgetProvider / RemoteViews) cannot run under
// `flutter test`; what IS tested here is everything the app decides:
// deep-link parsing, opacity / theme resolution, "next connection"
// picking, the widget display model, and the sync that writes the widget
// data (with the home_widget MethodChannel mocked).
import 'package:ace_remote/home_widget_data.dart';
import 'package:ace_remote/rdp_connections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

RdpConnection conn(
  String id, {
  String name = 'ace',
  String host = '100.101.127.41',
  int port = 3389,
  bool trackpadMode = false,
  bool keyboardVisible = true,
  bool favorite = false,
}) =>
    RdpConnection(
      id: id,
      name: name,
      host: host,
      port: port,
      trackpadMode: trackpadMode,
      keyboardVisible: keyboardVisible,
      favorite: favorite,
    );

void main() {
  group('opacity', () {
    test('clamps to 0..100', () {
      expect(clampWidgetOpacity(0), 0);
      expect(clampWidgetOpacity(100), 100);
      expect(clampWidgetOpacity(60), 60);
      expect(clampWidgetOpacity(-5), 0);
      expect(clampWidgetOpacity(150), 100);
    });

    test('converts to an alpha channel (0 = transparent, 100 = opaque)',
        () {
      expect(widgetOpacityToAlpha(0), 0);
      expect(widgetOpacityToAlpha(100), 255);
      expect(widgetOpacityToAlpha(50), 128);
      expect(widgetOpacityToAlpha(-10), 0);
      expect(widgetOpacityToAlpha(120), 255);
    });
  });

  group('theme resolution', () {
    test('explicit light/dark wins over the phone', () {
      expect(
          resolveWidgetDark(
              mode: ThemeMode.light, systemBrightness: Brightness.dark),
          isFalse);
      expect(
          resolveWidgetDark(
              mode: ThemeMode.dark, systemBrightness: Brightness.light),
          isTrue);
    });

    test('"Theo điện thoại" follows the phone', () {
      expect(
          resolveWidgetDark(
              mode: ThemeMode.system, systemBrightness: Brightness.light),
          isFalse);
      expect(
          resolveWidgetDark(
              mode: ThemeMode.system, systemBrightness: Brightness.dark),
          isTrue);
    });
  });

  group('deep links', () {
    test('connect carries the connection id', () {
      expect(parseHomeWidgetUri(Uri.parse('aceremote://connect/abc')),
          const HomeWidgetAction(HomeWidgetActionKind.connect, 'abc'));
      expect(homeWidgetConnectUri('abc').toString(),
          'aceremote://connect/abc');
    });

    test('connect without an id just opens the app', () {
      expect(parseHomeWidgetUri(Uri.parse('aceremote://connect')),
          const HomeWidgetAction(HomeWidgetActionKind.openApp));
    });

    test('action URIs parse', () {
      expect(parseHomeWidgetUri(Uri.parse('aceremote://toggle-trackpad')),
          const HomeWidgetAction(HomeWidgetActionKind.toggleTrackpad));
      expect(parseHomeWidgetUri(Uri.parse('aceremote://toggle-keyboard')),
          const HomeWidgetAction(HomeWidgetActionKind.toggleKeyboard));
      expect(parseHomeWidgetUri(Uri.parse('aceremote://next-connection')),
          const HomeWidgetAction(HomeWidgetActionKind.nextConnection));
      expect(parseHomeWidgetUri(Uri.parse('aceremote://open')),
          const HomeWidgetAction(HomeWidgetActionKind.openApp));
      expect(homeWidgetActionUri('toggle-trackpad').toString(),
          'aceremote://toggle-trackpad');
    });

    test('anything else is ignored', () {
      expect(parseHomeWidgetUri(null), isNull);
      expect(parseHomeWidgetUri(Uri.parse('https://example.com')), isNull);
      expect(parseHomeWidgetUri(Uri.parse('aceremote://unknown')), isNull);
      expect(parseHomeWidgetUri(Uri.parse('other://connect/abc')), isNull);
    });
  });

  group('next connection', () {
    test('no connections -> null', () {
      expect(nextConnectionId([], 'a'), isNull);
    });

    test('one connection -> itself', () {
      expect(nextConnectionId([conn('a')], 'a'), 'a');
    });

    test('advances and wraps around', () {
      final list = [conn('a'), conn('b'), conn('c')];
      expect(nextConnectionId(list, 'a'), 'b');
      expect(nextConnectionId(list, 'b'), 'c');
      expect(nextConnectionId(list, 'c'), 'a');
    });

    test('unknown or missing current id -> first', () {
      final list = [conn('a'), conn('b')];
      expect(nextConnectionId(list, 'gone'), 'a');
      expect(nextConnectionId(list, null), 'a');
      expect(nextConnectionId(list, ''), 'a');
    });
  });

  group('HomeWidgetData', () {
    test('empty list -> "no connection" placeholder', () {
      final data = HomeWidgetData.fromConnections(
        connections: [],
        currentId: null,
        dark: true,
        opacity: 100,
      );
      expect(data.connection, isNull);
      expect(data.hasMultiple, isFalse);
      expect(data.name, 'Chưa có kết nối');
      expect(data.address, 'Mở app để thêm kết nối');
      expect(data.status, '');
    });

    test('picks the stored current connection', () {
      final list = [conn('a', name: 'ace'), conn('b', name: 'pc2')];
      final data = HomeWidgetData.fromConnections(
        connections: list,
        currentId: 'b',
        dark: false,
        opacity: 80,
      );
      expect(data.connection?.id, 'b');
      expect(data.name, 'pc2');
      expect(data.address, '100.101.127.41:3389');
      expect(data.hasMultiple, isTrue);
      expect(data.opacity, 80);
    });

    test('stale current id falls back to the favorite, then the first', () {
      final list = [
        conn('a', name: 'ace'),
        conn('b', name: 'pc2', favorite: true),
      ];
      expect(
          HomeWidgetData.fromConnections(
            connections: list,
            currentId: 'gone',
            dark: true,
            opacity: 100,
          ).connection?.id,
          'b');
      expect(
          HomeWidgetData.fromConnections(
            connections: [conn('a'), conn('b')],
            currentId: 'gone',
            dark: true,
            opacity: 100,
          ).connection?.id,
          'a');
    });

    test('status line reflects trackpad and keyboard', () {
      expect(
          HomeWidgetData.fromConnections(
            connections: [conn('a')],
            currentId: 'a',
            dark: true,
            opacity: 100,
          ).status,
          'Đã lưu • Chạm');
      expect(
          HomeWidgetData.fromConnections(
            connections: [
              conn('a', trackpadMode: true, keyboardVisible: false),
            ],
            currentId: 'a',
            dark: true,
            opacity: 100,
          ).status,
          'Đã lưu • Trackpad • Ẩn bàn phím');
    });

    test('opacity is clamped in the model', () {
      final data = HomeWidgetData.fromConnections(
        connections: [conn('a')],
        currentId: 'a',
        dark: true,
        opacity: 250,
      );
      expect(data.opacity, 100);
    });
  });

  group('HomeWidgetSync', () {
    const channel = MethodChannel('home_widget');

    Future<Map<String, Object?>> syncWithMock({
      required Map<String, Object> initialPrefs,
      required List<RdpConnection> connections,
      Brightness systemBrightness = Brightness.light,
    }) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      SharedPreferences.setMockInitialValues(initialPrefs);
      final prefs = await SharedPreferences.getInstance();
      await HomeWidgetSync.sync(
        prefs: prefs,
        connections: connections,
        systemBrightness: systemBrightness,
      );
      final saved = <String, Object?>{};
      for (final call in calls) {
        if (call.method == 'saveWidgetData') {
          final args = call.arguments as Map;
          saved[args['id'] as String] = args['data'];
        }
      }
      final updateCalls =
          calls.where((c) => c.method == 'updateWidget').toList();
      expect(updateCalls.length, 1);
      expect(
          (updateCalls.first.arguments as Map)['qualifiedAndroidName'],
          homeWidgetProviderQualifiedName);
      return saved;
    }

    testWidgets('writes the current connection, theme and opacity',
        (tester) async {
      final saved = await syncWithMock(
        initialPrefs: {
          'ace_remote_v1_theme': 2, // dark
          'ace_widget_opacity': 60,
          'ace_widget_current_id': 'b',
        },
        connections: [
          conn('a', name: 'ace'),
          conn('b',
              name: 'pc2',
              host: '10.0.0.2',
              port: 3390,
              trackpadMode: true,
              keyboardVisible: false,
              favorite: true),
        ],
        systemBrightness: Brightness.light,
      );
      expect(saved['widget_name'], 'pc2');
      expect(saved['widget_address'], '10.0.0.2:3390');
      expect(saved['widget_status'], 'Đã lưu • Trackpad • Ẩn bàn phím');
      expect(saved['widget_trackpad'], true);
      expect(saved['widget_keyboard'], false);
      expect(saved['widget_has_next'], true);
      // Explicit dark theme wins over the light phone.
      expect(saved['widget_dark'], true);
      expect(saved['widget_opacity'], 60);
      expect(saved['widget_connection_id'], 'b');
    });

    testWidgets('"Theo điện thoại" resolves against the phone brightness',
        (tester) async {
      final saved = await syncWithMock(
        initialPrefs: {'ace_remote_v1_theme': 0}, // system
        connections: [conn('a')],
        systemBrightness: Brightness.dark,
      );
      expect(saved['widget_dark'], true);
      expect(saved['widget_has_next'], false);
      expect(saved['widget_opacity'], widgetOpacityDefault);
    });

    testWidgets('repairs a stale stored current id', (tester) async {
      final saved = await syncWithMock(
        initialPrefs: {'ace_widget_current_id': 'gone'},
        connections: [conn('a', name: 'ace'), conn('b', name: 'pc2')],
      );
      expect(saved['widget_connection_id'], 'a');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(widgetCurrentConnectionKey), 'a');
    });

    testWidgets('empty list writes the placeholder', (tester) async {
      final saved = await syncWithMock(
        initialPrefs: {},
        connections: [],
      );
      expect(saved['widget_name'], 'Chưa có kết nối');
      expect(saved['widget_status'], '');
      expect(saved['widget_has_next'], false);
      expect(saved['widget_connection_id'], '');
    });
  });
}
