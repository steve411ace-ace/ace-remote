import 'dart:convert';
import 'dart:io';
import 'package:ace_remote/agent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SendKeys escapes each literal, preserves Vietnamese', () {
    expect(escapeSendKeys('Việt +^%~(){}'), 'Việt {+}{^}{%}{~}{(}{)}{{}{}}');
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
      'HTTP health metadata, screenshot monitor query, JSON command and errors',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <String>[];
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
        expect(data['button'], 'right');
        expect(data['x'], -1152);
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
    expect(await a.screenshot(2), [1, 2, 3]);
    expect(received.last, 'GET /screenshot?monitor=2');
    await expectLater(a.command('/key', {'key': 'Win+L'}),
        throwsA(predicate((e) => e.toString().contains('Hết phiên'))));
    a.dispose();
    await server.close(force: true);
  });
}
