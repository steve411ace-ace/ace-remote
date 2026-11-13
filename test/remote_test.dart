import 'package:ace_remote/agent.dart';
import 'package:ace_remote/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Trackpad: right click, movement, scroll, drag down/up',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Trackpad(
      onMove: (_) => events.add('move'),
      onClick: (b) => events.add(b),
      onScroll: (_) => events.add('scroll'),
      onDrag: (v) => events.add('drag:$v'),
    ))));
    final p = tester.getCenter(find.byType(Trackpad));
    final a = await tester.startGesture(p, pointer: 1);
    final b = await tester.startGesture(p + const Offset(20, 0), pointer: 2);
    await b.up();
    await a.up();
    expect(events, ['right']);
    events.clear();
    final c = await tester.startGesture(p);
    await c.moveBy(const Offset(20, 10));
    await c.up();
    expect(events, ['move']);
    events.clear();
    final d = await tester.startGesture(p, pointer: 3);
    final e = await tester.startGesture(p + const Offset(20, 0), pointer: 4);
    await e.moveBy(const Offset(0, 20));
    await e.up();
    await d.up();
    expect(events, ['scroll']);
    events.clear();
    final f = await tester.startGesture(p);
    await tester.pump(const Duration(milliseconds: 510));
    await f.moveBy(const Offset(20, 0));
    await f.up();
    expect(events, ['drag:true', 'move', 'drag:false']);
  });
  testWidgets('Shutdown requires two approvals; cancel sends nothing',
      (tester) async {
    final a = Agent(baseUrl: defaultBaseUrl, mock: true);
    await a.health();
    await tester.pumpWidget(
        MaterialApp(home: RemotePage(agent: a, pollMs: () => 1000)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tắt máy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.text('Xác nhận lần 2'), findsOneWidget);
    expect(a.log.value.where((s) => s.contains('/power')), isEmpty);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(a.log.value.where((s) => s.contains('/power')), isEmpty);
    await tester.pumpWidget(const SizedBox());
    a.dispose();
  });
}
