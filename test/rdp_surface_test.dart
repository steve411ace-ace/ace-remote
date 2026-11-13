import 'package:ace_remote/agent.dart';
import 'package:ace_remote/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

void main() {
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
}
