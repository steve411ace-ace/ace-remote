import 'package:ace_remote/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'PIN enrollment, encrypted-storage hash, five-minute idle lock and wrong PIN',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    var now = DateTime(2026, 11, 13);
    await tester.pumpWidget(AceApp(now: () => now));
    await tester.pumpAndSettle();
    expect(find.text('Đặt PIN lần đầu'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '1234');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Lưu PIN'));
    await tester.pumpAndSettle();
    expect(find.text('ace — Windows'), findsOneWidget);
    final stored = await const FlutterSecureStorage().readAll();
    expect(stored['ace_pin_hash'], isNot('1234'));
    expect(stored['ace_pin_salt'], isNotEmpty);
    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Mở khóa phiên'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('Mở khóa'));
    await tester.pumpAndSettle();
    expect(find.text('Mở khóa phiên'), findsOneWidget);
    expect(find.textContaining('Chưa mở khóa.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Mở khóa'));
    await tester.pumpAndSettle();
    expect(find.text('ace — Windows'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
