// Step 27: home-screen widget (Android 4x2) data model + sync.
//
// The widget itself is native (AppWidgetProvider + RemoteViews, see
// android/app/src/main/kotlin/vn/aceremote/app/AceRemoteWidgetProvider.kt).
// This file is the Dart side that both the app and the widget agree on:
//
// * `HomeWidgetSync` writes the widget's display data into the
//   `home_widget` SharedPreferences file (HomeWidgetPreferences) and asks
//   the plugin to refresh the widget. It reads the same storage the app
//   already uses (prefs key `rdp_connections` + per-id secure storage
//   from step 23, theme key `ace_remote_v1_theme` from step 24, and the
//   widget opacity key from this step) — the storage layout from step 23
//   is NOT changed.
// * Deep links (`aceremote://...`) are how every widget tap reaches the
//   app. ALL widget buttons use a launch intent (open the app), NOT a
//   background callback — see the doc for why: home_widget's background
//   isolate runs a bare FlutterEngine without GeneratedPluginRegistrant,
//   so SharedPreferences / HomeWidget calls there throw
//   MissingPluginException. A tap opens the app, the app performs the
//   action, then syncs the widget back.
//
// Keys written into HomeWidgetPreferences (read by the native provider):
//   widget_name / widget_address / widget_status: connection display info.
//   widget_trackpad / widget_keyboard: current connection's quick toggles.
//   widget_has_next: true when > 1 saved connection (shows the switch key).
//   widget_dark: effective theme (app theme resolved against the phone).
//   widget_opacity: 0-100 (0 = fully transparent background).
//   widget_connection_id: id of the connection shown (for the connect tap).
library;

import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rdp_connections.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Fully qualified name of the native AppWidgetProvider (must match the
/// receiver declared in AndroidManifest.xml).
const String homeWidgetProviderQualifiedName =
    'vn.aceremote.app.AceRemoteWidgetProvider';

/// Opacity of the widget background, 0 (fully transparent) .. 100 (opaque).
/// Stored in the app's SharedPreferences; the native provider reads the
/// resolved value from HomeWidgetPreferences instead.
const String widgetOpacityKey = 'ace_widget_opacity';
const int widgetOpacityDefault = 100;

/// Id of the connection currently shown on the widget (last opened, or the
/// first/favorite one). Stored in the app's SharedPreferences so a widget
/// tap can find the same connection the app last showed.
const String widgetCurrentConnectionKey = 'ace_widget_current_id';

// Keys in HomeWidgetPreferences (shared app <-> widget).
const String _widgetNameKey = 'widget_name';
const String _widgetAddressKey = 'widget_address';
const String _widgetStatusKey = 'widget_status';
const String _widgetTrackpadKey = 'widget_trackpad';
const String _widgetKeyboardKey = 'widget_keyboard';
const String _widgetHasNextKey = 'widget_has_next';
const String _widgetDarkKey = 'widget_dark';
const String _widgetOpacityDataKey = 'widget_opacity';
const String _widgetConnectionIdKey = 'widget_connection_id';

// ---------------------------------------------------------------------------
// Deep links
// ---------------------------------------------------------------------------

const String homeWidgetScheme = 'aceremote';
const String homeWidgetConnectHost = 'connect';
const String homeWidgetToggleTrackpadHost = 'toggle-trackpad';
const String homeWidgetToggleKeyboardHost = 'toggle-keyboard';
const String homeWidgetNextConnectionHost = 'next-connection';
const String homeWidgetOpenHost = 'open';

/// Tap the widget body (or its "Kết nối" key): open the app and connect
/// straight to [connectionId].
Uri homeWidgetConnectUri(String connectionId) => Uri(
      scheme: homeWidgetScheme,
      host: homeWidgetConnectHost,
      pathSegments: <String>[connectionId],
    );

/// One URI per widget action key (no path needed).
Uri homeWidgetActionUri(String host) =>
    Uri(scheme: homeWidgetScheme, host: host);

enum HomeWidgetActionKind {
  openApp,
  connect,
  toggleTrackpad,
  toggleKeyboard,
  nextConnection,
}

/// One parsed widget deep link. `connectionId` is only set for [connect].
class HomeWidgetAction {
  const HomeWidgetAction(this.kind, [this.connectionId = '']);

  final HomeWidgetActionKind kind;
  final String connectionId;

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetAction &&
      other.kind == kind &&
      other.connectionId == connectionId;

  @override
  int get hashCode => Object.hash(kind, connectionId);

  @override
  String toString() =>
      'HomeWidgetAction($kind${connectionId.isEmpty ? '' : ', $connectionId'})';
}

/// Parses a URI the app was launched/clicked with from the widget.
/// Returns null for anything that is not one of our widget deep links
/// (other schemes, other hosts, or a null URI) so the caller can ignore it.
HomeWidgetAction? parseHomeWidgetUri(Uri? uri) {
  if (uri == null || uri.scheme != homeWidgetScheme) return null;
  switch (uri.host) {
    case homeWidgetConnectHost:
      final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      return id.isEmpty
          ? const HomeWidgetAction(HomeWidgetActionKind.openApp)
          : HomeWidgetAction(HomeWidgetActionKind.connect, id);
    case homeWidgetToggleTrackpadHost:
      return const HomeWidgetAction(HomeWidgetActionKind.toggleTrackpad);
    case homeWidgetToggleKeyboardHost:
      return const HomeWidgetAction(HomeWidgetActionKind.toggleKeyboard);
    case homeWidgetNextConnectionHost:
      return const HomeWidgetAction(HomeWidgetActionKind.nextConnection);
    case homeWidgetOpenHost:
      return const HomeWidgetAction(HomeWidgetActionKind.openApp);
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Pure helpers (unit-tested)
// ---------------------------------------------------------------------------

/// Clamps an opacity value to the 0..100 range used by the Settings slider.
int clampWidgetOpacity(int value) => value.clamp(0, 100);

/// Converts opacity 0..100 to an ARGB alpha channel 0..255.
/// 0% = fully transparent, 100% = fully opaque.
int widgetOpacityToAlpha(int opacity) =>
    (clampWidgetOpacity(opacity) * 255 / 100).round();

/// Resolves the app's theme setting to the effective brightness the widget
/// must draw with. Same rule as the app's ThemeMode (step 24): an explicit
/// Sáng/Tối wins; "Theo điện thoại" follows the phone's system brightness.
bool resolveWidgetDark({
  required ThemeMode mode,
  required Brightness systemBrightness,
}) =>
    mode == ThemeMode.dark ||
    (mode == ThemeMode.system && systemBrightness == Brightness.dark);

/// Id of the connection that follows [currentId] in the Home display order
/// (favorites first, step 23), wrapping around to the first one. Returns
/// null when there is no connection at all. An unknown/stale [currentId]
/// resolves to the first connection.
String? nextConnectionId(
  List<RdpConnection> connections,
  String? currentId,
) {
  if (connections.isEmpty) return null;
  if (currentId == null || currentId.isEmpty) return connections.first.id;
  final index = connections.indexWhere((c) => c.id == currentId);
  if (index < 0) return connections.first.id;
  return connections[(index + 1) % connections.length].id;
}

// ---------------------------------------------------------------------------
// Widget display data
// ---------------------------------------------------------------------------

/// Everything the native widget needs to draw one frame. Built from the
/// same connection list the Home screen shows, so app and widget can never
/// disagree about which connection is "current".
class HomeWidgetData {
  const HomeWidgetData({
    required this.connection,
    required this.hasMultiple,
    required this.dark,
    required this.opacity,
  });

  /// The connection shown on the widget; null when nothing is saved yet.
  final RdpConnection? connection;

  /// True when more than one connection is saved (shows the switch key).
  final bool hasMultiple;

  /// Effective theme for the widget background/text.
  final bool dark;

  /// Background opacity 0..100 (already clamped).
  final int opacity;

  String get name => connection?.name ?? 'Chưa có kết nối';

  String get address =>
      connection?.address ?? 'Mở app để thêm kết nối';

  /// Short status line under the address. Empty when nothing is saved.
  String get status {
    final c = connection;
    if (c == null) return '';
    final trackpad = c.trackpadMode ? 'Trackpad' : 'Chạm';
    final keyboard = c.keyboardVisible ? '' : ' • Ẩn bàn phím';
    return 'Đã lưu • $trackpad$keyboard';
  }

  /// Picks the connection to show: the stored current id when it still
  /// exists, otherwise the favorite, otherwise the first saved connection.
  factory HomeWidgetData.fromConnections({
    required List<RdpConnection> connections,
    required String? currentId,
    required bool dark,
    required int opacity,
  }) {
    RdpConnection? current;
    if (currentId != null && currentId.isNotEmpty) {
      for (final c in connections) {
        if (c.id == currentId) {
          current = c;
          break;
        }
      }
    }
    current ??= connections.isEmpty
        ? null
        : connections.firstWhere(
            (c) => c.favorite,
            orElse: () => connections.first,
          );
    return HomeWidgetData(
      connection: current,
      hasMultiple: connections.length > 1,
      dark: dark,
      opacity: clampWidgetOpacity(opacity),
    );
  }
}

// ---------------------------------------------------------------------------
// Sync (app -> widget)
// ---------------------------------------------------------------------------

/// Writes the widget's display data and asks the plugin to redraw it.
/// Best-effort by design: it never throws, so a missing/broken widget
/// plugin can never break the app itself.
class HomeWidgetSync {
  /// Syncs from already-loaded app state (theme, opacity, connections).
  /// Also repairs the stored current-connection id when it is missing or
  /// points at a deleted connection, so the widget never shows a stale id.
  static Future<void> sync({
    required SharedPreferences prefs,
    required List<RdpConnection> connections,
    required Brightness systemBrightness,
  }) async {
    try {
      final themeIndex = prefs.getInt('ace_remote_v1_theme') ?? 0;
      final theme = ThemeMode.values[themeIndex.clamp(0, 2)];
      final opacity =
          prefs.getInt(widgetOpacityKey) ?? widgetOpacityDefault;
      final storedCurrent = prefs.getString(widgetCurrentConnectionKey);
      final data = HomeWidgetData.fromConnections(
        connections: connections,
        currentId: storedCurrent,
        dark: resolveWidgetDark(
          mode: theme,
          systemBrightness: systemBrightness,
        ),
        opacity: opacity,
      );
      final resolvedId = data.connection?.id ?? '';
      if (resolvedId.isNotEmpty && resolvedId != storedCurrent) {
        await prefs.setString(widgetCurrentConnectionKey, resolvedId);
      }
      await HomeWidget.saveWidgetData<String>(_widgetNameKey, data.name);
      await HomeWidget.saveWidgetData<String>(
          _widgetAddressKey, data.address);
      await HomeWidget.saveWidgetData<String>(_widgetStatusKey, data.status);
      await HomeWidget.saveWidgetData<bool>(
          _widgetTrackpadKey, data.connection?.trackpadMode ?? false);
      await HomeWidget.saveWidgetData<bool>(
          _widgetKeyboardKey, data.connection?.keyboardVisible ?? true);
      await HomeWidget.saveWidgetData<bool>(_widgetHasNextKey, data.hasMultiple);
      await HomeWidget.saveWidgetData<bool>(_widgetDarkKey, data.dark);
      await HomeWidget.saveWidgetData<int>(_widgetOpacityDataKey, data.opacity);
      await HomeWidget.saveWidgetData<String>(
          _widgetConnectionIdKey, resolvedId);
      await HomeWidget.updateWidget(
        qualifiedAndroidName: homeWidgetProviderQualifiedName,
      );
    } catch (_) {
      // Widget sync is best-effort; the app must keep working without it.
    }
  }

  /// Loads the app state itself (prefs + connection list) and syncs.
  /// Call this after any change the widget should reflect: opening a
  /// connection, editing/favoriting/deleting one, changing the theme or
  /// the widget opacity, or toggling trackpad/keyboard from the widget.
  static Future<void> syncFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final connections = await RdpConnectionStore().load();
      await sync(
        prefs: prefs,
        connections: connections,
        systemBrightness:
            PlatformDispatcher.instance.platformBrightness,
      );
    } catch (_) {
      // Best-effort, see [sync].
    }
  }

  /// Remembers which connection the widget should show (called when the
  /// user opens a connection from Home or from the widget itself).
  static Future<void> setCurrentId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(widgetCurrentConnectionKey, id);
    } catch (_) {
      // Best-effort, see [sync].
    }
  }
}
