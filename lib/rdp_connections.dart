import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rdp_credentials.dart';

// Saved RDP connections (step 23, item 6): the Home screen lists them like
// the "PC Connections" section of Microsoft Remote Desktop, and tapping a
// card connects right away with the saved host/port/user/password.
//
// Storage split (no plaintext password anywhere):
// - SharedPreferences key `rdp_connections`: a JSON list of display records
//   (id, name, host, port). The username is NOT in this JSON.
// - Secure storage (same encrypted file as step 21, `ace_rdp_credentials`):
//   `rdp_username_<id>` and `rdp_password_<id>` per connection, so each
//   connection keeps its own credentials and deleting it wipes them.

/// Which on-screen click keys flank Space (step 36, manual config — An:
/// "Thay hẳn, chỉnh tay thôi"). `showBoth` is the default (the pre-step-34
/// behaviour). `hideRight` keeps Left — the one needed to click while
/// swiping on the keyboard to move the mouse — and gives Space Right's
/// width; `hideBoth` hides both and Space takes both widths. Stored as a
/// string in the JSON record; old records without the key fall back to
/// `showBoth`.
enum ClickKeys { showBoth, hideRight, hideBoth }

/// One saved connection. `username` is filled in by the store from secure
/// storage; it is never part of [toJson]. The per-connection settings
/// (step 23 redesign, 04:03) live in the JSON record: `trackpadMode`
/// (false = touch, true = trackpad), `keyboardVisible` (false = the remote
/// screen fills the whole page), `favorite` (pinned to the top of the
/// list), `clickKeys` (step 36), and `trackpadArea` (step 37: a dedicated
/// trackpad strip under the keyboard, only when the phone is unfolded).
/// Older records without these keys get the defaults below.
class RdpConnection {
  const RdpConnection({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.username = '',
    this.trackpadMode = false,
    this.keyboardVisible = true,
    this.favorite = false,
    this.clickKeys = ClickKeys.showBoth,
    this.trackpadArea = false,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final bool trackpadMode;
  final bool keyboardVisible;
  final bool favorite;
  final ClickKeys clickKeys;
  final bool trackpadArea;

  String get address => '$host:$port';

  RdpConnection copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    bool? trackpadMode,
    bool? keyboardVisible,
    bool? favorite,
    ClickKeys? clickKeys,
    bool? trackpadArea,
  }) =>
      RdpConnection(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        trackpadMode: trackpadMode ?? this.trackpadMode,
        keyboardVisible: keyboardVisible ?? this.keyboardVisible,
        favorite: favorite ?? this.favorite,
        clickKeys: clickKeys ?? this.clickKeys,
        trackpadArea: trackpadArea ?? this.trackpadArea,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'trackpad': trackpadMode,
        'keyboard': keyboardVisible,
        'favorite': favorite,
        'clickKeys': clickKeys.name,
        'trackpadArea': trackpadArea,
      };

  factory RdpConnection.fromJson(Map<String, dynamic> json) => RdpConnection(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 3389,
        trackpadMode: json['trackpad'] as bool? ?? false,
        keyboardVisible: json['keyboard'] as bool? ?? true,
        favorite: json['favorite'] as bool? ?? false,
        clickKeys: ClickKeys.values.firstWhere(
            (v) => v.name == json['clickKeys'],
            orElse: () => ClickKeys.showBoth),
        trackpadArea: json['trackpadArea'] as bool? ?? false,
      );
}

String rdpConnectionUsernameKey(String id) => 'rdp_username_$id';
String rdpConnectionPasswordKey(String id) => 'rdp_password_$id';

class RdpConnectionStore {
  RdpConnectionStore({FlutterSecureStorage? secureStorage})
      : _storage = secureStorage ?? storage;

  final FlutterSecureStorage _storage;

  static const listKey = 'rdp_connections';

  /// Counter so two connections added in the same millisecond still get
  /// distinct ids (millisecond timestamps alone collide on fast taps and in
  /// tests, and two records with one id corrupt update/remove/favorites).
  static int _nextId = 0;

  /// The single connection the app had before saved connections existed.
  static const defaultConnection = RdpConnection(
    id: 'ace',
    name: 'ace — Windows',
    host: '100.101.127.41',
    port: 3389,
  );

  /// Loads the saved connections, favorites first (stable order otherwise).
  /// On the very first run the list is seeded
  /// with the default `ace` connection (and, if step 21 already saved a
  /// username/password, those are carried over to it so An does not have to
  /// type them again). An empty list stays empty: deleting every connection
  /// does not re-seed the default.
  Future<List<RdpConnection>> load() async {
    final connections = await _loadRaw();
    // Favorites first; Dart's sort is stable, so the rest keeps its order.
    connections.sort((a, b) =>
        (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0));
    return connections;
  }

  /// The stored list in insertion order (no favorite sorting). add/update/
  /// remove use this so the persisted order stays insertion order; only the
  /// displayed list (load()) is sorted.
  Future<List<RdpConnection>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(listKey);
    if (raw == null) {
      await prefs.setString(
          listKey, jsonEncode([defaultConnection.toJson()]));
      final user = await _storage.read(
          key: rdpUsernameKey, aOptions: rdpStorageOptions);
      final secret = await _storage.read(
          key: rdpPasswordKey, aOptions: rdpStorageOptions);
      if (user != null) {
        await _storage.write(
            key: rdpConnectionUsernameKey(defaultConnection.id),
            value: user,
            aOptions: rdpStorageOptions);
      }
      if (secret != null) {
        await _storage.write(
            key: rdpConnectionPasswordKey(defaultConnection.id),
            value: secret,
            aOptions: rdpStorageOptions);
      }
      return [defaultConnection.copyWith(username: user ?? '')];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [defaultConnection];
    final connections = <RdpConnection>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final record =
          RdpConnection.fromJson(Map<String, dynamic>.from(item));
      final user = await _storage.read(
          key: rdpConnectionUsernameKey(record.id),
          aOptions: rdpStorageOptions);
      connections.add(record.copyWith(username: user ?? ''));
    }
    return connections;
  }

  Future<void> _saveList(List<RdpConnection> connections) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        listKey, jsonEncode(connections.map((c) => c.toJson()).toList()));
  }

  /// Adds a connection and stores its credentials under its own id.
  Future<RdpConnection> add({
    required String name,
    required String host,
    required int port,
    String username = '',
    String password = '',
    bool trackpadMode = false,
    bool keyboardVisible = true,
    bool favorite = false,
    ClickKeys clickKeys = ClickKeys.showBoth,
    bool trackpadArea = false,
  }) async {
    final connection = RdpConnection(
      id: '${DateTime.now().millisecondsSinceEpoch}-${_nextId++}',
      name: name,
      host: host,
      port: port,
      username: username,
      trackpadMode: trackpadMode,
      keyboardVisible: keyboardVisible,
      favorite: favorite,
      clickKeys: clickKeys,
      trackpadArea: trackpadArea,
    );
    final connections = await _loadRaw();
    connections.add(connection);
    await _saveList(connections);
    await saveCredentials(connection.id,
        username: username, password: password);
    return connection;
  }

  /// Updates the display record and its credentials. `password` is only
  /// rewritten when given, so an edit that leaves the password field alone
  /// keeps the saved one.
  Future<void> update(RdpConnection connection, {String? password}) async {
    final connections = await _loadRaw();
    final index = connections.indexWhere((c) => c.id == connection.id);
    if (index < 0) return;
    connections[index] = connection;
    await _saveList(connections);
    await _storage.write(
        key: rdpConnectionUsernameKey(connection.id),
        value: connection.username,
        aOptions: rdpStorageOptions);
    if (password != null) {
      await _storage.write(
          key: rdpConnectionPasswordKey(connection.id),
          value: password,
          aOptions: rdpStorageOptions);
    }
  }

  /// Removes the connection and deletes its secure-storage credentials.
  Future<void> remove(String id) async {
    final connections = await _loadRaw();
    connections.removeWhere((c) => c.id == id);
    await _saveList(connections);
    await _storage.delete(
        key: rdpConnectionUsernameKey(id), aOptions: rdpStorageOptions);
    await _storage.delete(
        key: rdpConnectionPasswordKey(id), aOptions: rdpStorageOptions);
  }

  /// Writes a connection's credentials (also used to save back user/pass
  /// edited in the RDP form after a successful connect).
  Future<void> saveCredentials(String id,
      {required String username, required String password}) async {
    await _storage.write(
        key: rdpConnectionUsernameKey(id),
        value: username,
        aOptions: rdpStorageOptions);
    await _storage.write(
        key: rdpConnectionPasswordKey(id),
        value: password,
        aOptions: rdpStorageOptions);
  }

  Future<String> usernameFor(String id) async =>
      await _storage.read(
          key: rdpConnectionUsernameKey(id), aOptions: rdpStorageOptions) ??
      '';

  Future<String> passwordFor(String id) async =>
      await _storage.read(
          key: rdpConnectionPasswordKey(id), aOptions: rdpStorageOptions) ??
      '';
}
