import 'package:ace_remote/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Settings shows only the theme choices, no agent items',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SettingsPage(
            theme: ThemeMode.system, onThemeChanged: (_) async {})));
    await tester.pumpAndSettle();
    // The three theme choices are the whole page.
    expect(find.text('Sáng'), findsOneWidget);
    expect(find.text('Tối'), findsOneWidget);
    expect(find.text('Theo điện thoại'), findsOneWidget);
    // The old agent-era items are gone.
    expect(find.text('Địa chỉ agent (Base URL)'), findsNothing);
    expect(find.text('Kiểm tra kết nối'), findsNothing);
    expect(find.text('Tốc độ ảnh'), findsNothing);
    expect(find.text('Lưu cài đặt'), findsNothing);
    expect(find.textContaining('Máy ngủ hẳn'), findsNothing);
    expect(find.textContaining('Agent PC'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tapping a theme applies it immediately', (tester) async {
    final applied = <ThemeMode>[];
    await tester.pumpWidget(MaterialApp(
        home: SettingsPage(
            theme: ThemeMode.system,
            onThemeChanged: (mode) async => applied.add(mode))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tối'));
    await tester.pumpAndSettle();
    expect(applied, [ThemeMode.dark]);
    // The tapped option is now the selected radio.
    expect(
        tester
            .widget<RadioGroup<ThemeMode>>(
                find.byType(RadioGroup<ThemeMode>))
            .groupValue,
        ThemeMode.dark);
    await tester.tap(find.text('Sáng'));
    await tester.pumpAndSettle();
    expect(applied, [ThemeMode.dark, ThemeMode.light]);
    expect(
        tester
            .widget<RadioGroup<ThemeMode>>(
                find.byType(RadioGroup<ThemeMode>))
            .groupValue,
        ThemeMode.light);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Settings starts with the current theme selected',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SettingsPage(
            theme: ThemeMode.dark, onThemeChanged: (_) async {})));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RadioGroup<ThemeMode>>(
                find.byType(RadioGroup<ThemeMode>))
            .groupValue,
        ThemeMode.dark);
    await tester.pumpWidget(const SizedBox());
  });
}
