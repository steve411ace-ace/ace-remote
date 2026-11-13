import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ace_remote/agent.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Key endpoint receives SendKeys chord syntax', () {
    expect(sendKeysChord('Ctrl+V'), '^v');
    expect(sendKeysChord('Ctrl+Shift+Esc'), '^+{ESC}');
    expect(sendKeysChord('Alt+Tab'), '%{TAB}');
  });
  test('Secondary monitor maps scaled center and clamps edges', () {
    const d = DisplayInfo(2, -1920, 0, 1536, 864);
    expect(d.map(const Offset(480, 270), const Size(960, 540)),
        const Offset(-1152, 432));
    expect(d.map(const Offset(960, 540), const Size(960, 540)),
        const Offset(-385, 863));
    expect(d.map(const Offset(-10, -10), const Size(960, 540)),
        const Offset(-1920, 0));
  });
  test('Screens metadata sorts primary first and crops the virtual image', () async {
    final a = Agent(baseUrl: defaultBaseUrl, client: MockClient((_) async {
      return http.Response(jsonEncode({
        'ok': true,
        'cursorX': -1200,
        'cursorY': 320,
        'width': 1920,
        'height': 1080,
        'screens': [
          {'device': 'secondary', 'primary': false, 'x': -1920, 'y': 0,
            'width': 1536, 'height': 864},
          {'device': 'primary', 'primary': true, 'x': 0, 'y': 0,
            'width': 1920, 'height': 1080},
        ],
      }), 200);
    }));
    addTearDown(a.dispose);
    await a.health();
    expect(a.virtualSize, const Size(3840, 1080));
    expect(a.virtualOrigin, const Offset(-1920, 0));
    expect(a.displays.first.x, 0);
    expect(a.displays.first.screenshotIndex, 1);
    expect(a.displays.last.screenshotIndex, 0);
    expect(a.canSelect, isTrue);
    expect(a.cursor, const Offset(-1200, 320));
    expect(a.capabilities, contains('relative_move'));
    expect(a.capabilities, isNot(contains('power')));
    expect(a.capabilities, isNot(contains('mouse_drag')));
    final secondary = a.displays.last;
    expect(secondary.id, 2);
    expect(secondary.cropRect(a.virtualOrigin, a.virtualSize,
        const Size(3840, 1080)), const Rect.fromLTWH(0, 0, 1536, 864));
    expect(secondary.cropRect(a.virtualOrigin, a.virtualSize,
        const Size(1920, 540)), const Rect.fromLTWH(0, 0, 768, 432));
    expect(a.displays.first.cropRect(a.virtualOrigin, a.virtualSize,
        const Size(3840, 1080)), const Rect.fromLTWH(1920, 0, 1920, 1080));
    // Points are local to the displayed crop, not to the entire screenshot.
    expect(secondary.map(const Offset(384, 216), const Size(768, 432)),
        const Offset(-1152, 432));
    expect(a.displays.first.map(const Offset(480, 270), const Size(960, 540)),
        const Offset(960, 540));
  });
  test('Control command retries once and succeeds without reporting an error', () async {
    final requests = <http.Request>[];
    final a = Agent(baseUrl: defaultBaseUrl, client: MockClient((request) async {
      requests.add(request);
      if (requests.length == 1) throw http.ClientException('connection reset');
      return http.Response('{}', 200);
    }));
    addTearDown(a.dispose);
    await a.command('/click', {'button': 'left', 'x': -1152, 'y': 432});
    expect(requests, hasLength(2));
    expect(requests.map((r) => r.method), everyElement('POST'));
    expect(requests.map((r) => r.url.path), everyElement('/click'));
    expect(requests[1].body, requests[0].body);
    expect(jsonDecode(requests[1].body)['x'], -1152);
  });
  test('Control failure is reported only after the single retry fails', () async {
    var attempts = 0;
    final retryStarted = Completer<void>();
    final retryResponse = Completer<http.Response>();
    final a = Agent(baseUrl: defaultBaseUrl, client: MockClient((_) async {
      attempts++;
      if (attempts == 1) return http.Response('temporary failure', 503);
      retryStarted.complete();
      return retryResponse.future;
    }));
    addTearDown(a.dispose);
    var finished = false;
    final command = a.command('/key', {'key': 'Enter'});
    final checked = expectLater(command, throwsException).then((_) {
      finished = true;
    });
    await retryStarted.future;
    expect(attempts, 2);
    expect(finished, isFalse);
    retryResponse.complete(http.Response('still unavailable', 503));
    await checked;
    expect(attempts, 2);
  });
  test('/type preserves actual agent error after retry', () async {
    var attempts = 0;
    final bodies = <Map<String, dynamic>>[];
    final a = Agent(baseUrl: defaultBaseUrl, client: MockClient((request) async {
      attempts++;
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(jsonEncode({'ok': false, 'error': 'SendKeys failed'}), 500);
    }));
    addTearDown(a.dispose);
    await expectLater(a.command('/type', {'text': 'Tiếng Việt +{}'}),
        throwsA(predicate((e) => e.toString().contains('SendKeys failed'))));
    expect(attempts, 2);
    expect(bodies.map((b) => b['text']), everyElement('Tiếng Việt +{}'));
  });
  test('Command rejects an explicit ok false response', () async {
    final a = Agent(baseUrl: defaultBaseUrl, client: MockClient((_) async =>
        http.Response('{"ok":false,"error":"typing failed"}', 200)));
    addTearDown(a.dispose);
    await expectLater(a.command('/type', {'text': 'Việt'}),
        throwsA(predicate((e) => e.toString().contains('typing failed'))));
  });
  test('Base URL editable; rejects embedded credentials and invalid URL', () {
    final a = Agent(baseUrl: 'http://localhost:1234/proxy/');
    expect(a.uri('/health').toString(), 'http://localhost:1234/proxy/health');
    a.baseUrl = 'ftp://localhost';
    expect(() => a.uri('/health'), throwsException);
    a.baseUrl = 'http://user:secret@localhost';
    expect(() => a.uri('/health'), throwsException);
    a.dispose();
  });
  test('Mock logs commands and exposes both real coordinate origins', () async {
    final a = Agent(baseUrl: defaultBaseUrl, mock: true);
    await a.health();
    await a.command('/click', {'button': 'right', 'monitor': 2});
    expect(a.canSelect, isTrue);
    expect(a.displays.last.x, -1920);
    expect(a.log.value.last, contains('"button":"right"'));
    a.dispose();
  });
  test(
      'HTTP legacy health metadata, JPEG screenshot query, JSON command and errors',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <String>[];
    final clicks = <dynamic>[];
    server.listen((r) async {
      received.add('${r.method} ${r.uri}');
      if (r.uri.path == '/health') {
        r.response.write(jsonEncode({
          'capabilities': ['select_monitor'],
          'monitors': [
            {'id': 2, 'x': -1920, 'y': 0, 'width': 1536, 'height': 864}
          ]
        }));
      } else if (r.uri.path == '/click') {
        final data = jsonDecode(await utf8.decoder.bind(r).join());
        clicks.add(data);
        r.response.write('{}');
      } else if (r.uri.path == '/screenshot') {
        r.response.add([1, 2, 3]);
      } else {
        r.response.statusCode = 401;
      }
      await r.response.close();
    });
    final a = Agent(baseUrl: 'http://127.0.0.1:${server.port}');
    await a.health();
    expect(a.displays.single.x, -1920);
    expect(a.canSelect, isTrue);
    await a.command('/click', {'button': 'right', 'x': -1152});
    expect(clicks.single['button'], 'right');
    expect(clicks.single['x'], -1152);
    expect(await a.screenshot(2), [1, 2, 3]);
    expect(received.last, 'GET /screenshot?monitor=2&format=jpeg&quality=70&scale=0.5');
    await expectLater(a.command('/key', {'key': 'Win+L'}),
        throwsA(predicate((e) => e.toString().contains('Hết phiên'))));
    a.dispose();
    await server.close(force: true);
  });
}
