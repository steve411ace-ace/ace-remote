import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const defaultBaseUrl = 'http://100.101.127.41:8765';
String escapeSendKeys(String text) => text
    .split('')
    .map((c) =>
        const {
          '+': '{+}',
          '^': '{^}',
          '%': '{%}',
          '~': '{~}',
          '(': '{(}',
          ')': '{)}',
          '{': '{{}',
          '}': '{}}'
        }[c] ??
        c)
    .join();

class DisplayInfo {
  const DisplayInfo(this.id, this.x, this.y, this.width, this.height);
  final int id, x, y, width, height;
  Offset map(Offset point, Size image) => Offset(
      x + (point.dx / image.width * width).clamp(0, width - 1),
      y + (point.dy / image.height * height).clamp(0, height - 1));
}

class Agent {
  Agent({required this.baseUrl, this.mock = false});
  String baseUrl;
  final bool mock;
  final http.Client _client = http.Client();
  final ValueNotifier<List<String>> log = ValueNotifier([]);
  List<DisplayInfo> displays = [];
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
        throw Exception(
            'Agent trả lỗi ${r.statusCode}. Kiểm tra endpoint và địa chỉ.');
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
        const DisplayInfo(2, -1920, 0, 1536, 864)
      ];
      capabilities = {'select_monitor', 'power', 'mouse_drag', 'relative_move'};
      record('GET /health → 200 (mô phỏng)');
      return;
    }
    final r = await request('/health');
    displays = [];
    capabilities = {};
    try {
      final body = jsonDecode(r.body);
      if (body is Map) {
        capabilities = Set<String>.from(body['capabilities'] ?? []);
        for (final d in body['monitors'] ?? []) {
          displays.add(DisplayInfo(d['id'] as int, d['x'] as int, d['y'] as int,
              d['width'] as int, d['height'] as int));
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
    await request(endpoint, data: data);
  }

  Future<Uint8List> screenshot(int monitor) async {
    if (!mock) {
      return (await request('/screenshot', query: {'monitor': '$monitor'}))
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
