import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;

const defaultBaseUrl = 'http://100.101.127.41:18765';
// /type accepts raw text: the Windows agent owns SendKeys escaping.
String sendKeysChord(String chord) {
  if (chord.split('+').contains('Win')) return chord;
  const modifiers = {'Ctrl': '^', 'Alt': '%', 'Shift': '+'};
  const special = {
    'Enter': 'ENTER',
    'Backspace': 'BACKSPACE',
    'Tab': 'TAB',
    'Escape': 'ESC',
    'Esc': 'ESC',
    'Delete': 'DEL',
    'Space': ' ',
    'Left': 'LEFT',
    'Right': 'RIGHT',
    'Up': 'UP',
    'Down': 'DOWN',
    'PrintScreen': 'PRTSC',
  };
  return chord.split('+').map((part) {
    if (modifiers.containsKey(part)) return modifiers[part]!;
    if (part.length == 1) return part.toLowerCase();
    if (part == 'Space') return ' ';
    return '{${special[part] ?? part}}';
  }).join();
}

class DisplayInfo {
  const DisplayInfo(this.id, this.x, this.y, this.width, this.height,
      {this.screenshotIndex = 0});
  final int id, x, y, width, height;
  final int screenshotIndex;
  Rect cropRect(Offset origin, Size virtualSize, Size imageSize) =>
      Rect.fromLTWH(
          (x - origin.dx) * imageSize.width / virtualSize.width,
          (y - origin.dy) * imageSize.height / virtualSize.height,
          width * imageSize.width / virtualSize.width,
          height * imageSize.height / virtualSize.height);
  Offset map(Offset point, Size image) => Offset(
      x + (point.dx / image.width * width).clamp(0, width - 1),
      y + (point.dy / image.height * height).clamp(0, height - 1));
}

class Agent {
  Agent({required this.baseUrl, this.mock = false, http.Client? client})
      : _client = client ?? http.Client();
  String baseUrl;
  final bool mock;
  final http.Client _client;
  Size virtualSize = const Size(3840, 1080);
  Offset get virtualOrigin => displays.isEmpty
      ? Offset.zero
      : Offset(
          displays.map((d) => d.x).reduce((a, b) => a < b ? a : b).toDouble(),
          displays.map((d) => d.y).reduce((a, b) => a < b ? a : b).toDouble());
  final ValueNotifier<List<String>> log = ValueNotifier([]);
  List<DisplayInfo> displays = [];
  Offset? cursor;
  Set<String> capabilities = {};
  bool get canSelect => capabilities.contains('select_monitor');
  void record(String s) {
    log.value = [...log.value, s].reversed.take(100).toList().reversed.toList();
  }

  Uri uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse(baseUrl.trim());
    if (!['http', 'https'].contains(u.scheme) ||
        u.host.isEmpty ||
        u.userInfo.isNotEmpty ||
        u.hasQuery ||
        u.hasFragment) {
      throw Exception(
          'Sai địa chỉ. Nhập URL http hoặc https không chứa tài khoản, query hay fragment.');
    }
    return u.replace(
        path: '${u.path.replaceAll(RegExp(r'/$'), '')}$path',
        queryParameters: query);
  }

  Future<http.Response> request(String path,
      {Map<String, dynamic>? data, Map<String, String>? query}) async {
    try {
      final u = uri(path, query);
      final r = await (data == null
              ? _client.get(u)
              : _client.post(u,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(data)))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 401 || r.statusCode == 403) {
        throw Exception('Hết phiên hoặc chưa được cấp quyền truy cập.');
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        String detail = r.body;
        try {
          final body = jsonDecode(r.body);
          if (body is Map && body['error'] != null) {
            detail = body['error'].toString();
          }
        } on FormatException {
          // Older proxies may return plain text.
        }
        throw Exception('Agent trả lỗi ${r.statusCode}: $detail');
      }
      return r;
    } on TimeoutException {
      throw Exception('Không thấy máy: kết nối quá hạn.');
    } on http.ClientException {
      throw Exception('Không thấy máy. Kiểm tra Tailscale và Base URL.');
    }
  }

  Future<void> health() async {
    if (mock) {
      displays = [
        const DisplayInfo(1, 0, 0, 1920, 1080),
        const DisplayInfo(2, -1920, 0, 1536, 864, screenshotIndex: 1)
      ];
      capabilities = {'select_monitor', 'power', 'mouse_drag', 'relative_move'};
      record('GET /health → 200 (mô phỏng)');
      return;
    }
    final r = await request('/health');
    displays = [];
    capabilities = {};
    cursor = null;
    try {
      final body = jsonDecode(r.body);
      if (body is Map) {
        capabilities = Set<String>.from(body['capabilities'] ?? []);
        if (body['cursorX'] is num && body['cursorY'] is num) {
          cursor = Offset((body['cursorX'] as num).toDouble(),
              (body['cursorY'] as num).toDouble());
        }
        // width/height describe PrimaryScreen, never the virtual desktop.
        final screens =
            List<dynamic>.from(body['screens'] ?? body['monitors'] ?? []);
        final indexedScreens = [
          for (var i = 0; i < screens.length; i++)
            {...screens[i] as Map, '_screenshotIndex': i}
        ];
        // Primary first gives stable, familiar tab numbering even when Windows
        // enumerates the negative-origin secondary screen first.
        indexedScreens.sort((a, b) => (b['primary'] == true ? 1 : 0)
            .compareTo(a['primary'] == true ? 1 : 0));
        for (final d in indexedScreens) {
          displays.add(DisplayInfo(
              d['id'] as int? ?? displays.length + 1,
              d['x'] as int,
              d['y'] as int,
              d['width'] as int,
              d['height'] as int,
              screenshotIndex: d['_screenshotIndex'] as int));
        }
        if (displays.isNotEmpty) {
          final right = displays
              .map((d) => d.x + d.width)
              .reduce((a, b) => a > b ? a : b);
          final bottom = displays
              .map((d) => d.y + d.height)
              .reduce((a, b) => a > b ? a : b);
          virtualSize =
              Size(right - virtualOrigin.dx, bottom - virtualOrigin.dy);
          // Client-side crop and relative movement via absolute /move.
          capabilities.addAll({'select_monitor', 'relative_move'});
        }
      }
    } catch (_) {
      /* Legacy health may return plain text. No invented geometry. */
    }
  }

  Future<void> command(String endpoint, Map<String, dynamic> data) async {
    if (mock) {
      record('POST $endpoint ${jsonEncode(data)}');
      return;
    }
    for (var attempt = 0;; attempt++) {
      try {
        final response = await request(endpoint, data: data);
        if (response.body.trimLeft().startsWith('{')) {
          final body = jsonDecode(response.body);
          if (body is Map && body['ok'] == false) {
            throw Exception(body['error'] ?? 'Agent từ chối lệnh $endpoint.');
          }
        }
        return;
      } catch (_) {
        if (attempt == 1) rethrow;
      }
    }
  }

  Future<Uint8List> screenshot(int monitor) async {
    if (!mock) {
      return (await request('/screenshot', query: {
        'monitor': '$monitor',
        'format': 'jpeg',
        'quality': '70',
        'scale': '0.5',
      }))
          .bodyBytes;
    }
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    c.drawRect(const Rect.fromLTWH(0, 0, 960, 540),
        Paint()..color = const Color(0xff123c50));
    for (var x = 0; x < 960; x += 80) {
      c.drawLine(Offset(x.toDouble(), 0), Offset(x.toDouble(), 540),
          Paint()..color = Colors.white24);
    }
    final p = TextPainter(
        text: TextSpan(
            text:
                'ace • Màn hình $monitor\nMÔ PHỎNG • Ảnh 960 × 540\nChạm để kiểm tra tọa độ\n${DateTime.now().toIso8601String()}',
            style: const TextStyle(color: Colors.white, fontSize: 28)),
        textDirection: TextDirection.ltr)
      ..layout();
    p.paint(c, const Offset(50, 100));
    final picture = recorder.endRecording();
    final img = await picture.toImage(960, 540);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  }

  void dispose() {
    _client.close();
    log.dispose();
  }
}
