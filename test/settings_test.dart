import 'package:ace_remote/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Settings shows theme choices and widget section, no agent items',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SettingsPage(
            theme: ThemeMode.system,
            onThemeChanged: (_) async {},
            widgetOpacity: 100,
            onWidgetOpacityChanged: (_) async {})));
    await tester.pumpAndSettle();
    // The three theme choices are the whole theme section.
    expect(find.text('Sáng'), findsOneWidget);
    expect(find.text('Tối'), findsOneWidget);
    expect(find.text('Theo điện thoại'), findsOneWidget);
    // Step 27: the widget section is present too.
    expect(find.text('Widget màn hình chính'), findsOneWidget);
    expect(find.text('Độ trong suốt của widget'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
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
            onThemeChanged: (mode) async => applied.add(mode),
            widgetOpacity: 100,
            onWidgetOpacityChanged: (_) async {})));
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
            theme: ThemeMode.dark,
            onThemeChanged: (_) async {},
            widgetOpacity: 100,
            onWidgetOpacityChanged: (_) async {})));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RadioGroup<ThemeMode>>(
                find.byType(RadioGroup<ThemeMode>))
            .groupValue,
        ThemeMode.dark);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Widget opacity slider shows the current value',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SettingsPage(
            theme: ThemeMode.system,
            onThemeChanged: (_) async {},
            widgetOpacity: 80,
            onWidgetOpacityChanged: (_) async {})));
    await tester.pumpAndSettle();
    expect(find.text('Widget màn hình chính'), findsOneWidget);
    expect(find.text('Độ trong suốt của widget'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 80);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Dragging the opacity slider saves on release',
      (tester) async {
    final applied = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: SettingsPage(
            theme: ThemeMode.system,
            onThemeChanged: (_) async {},
            widgetOpacity: 100,
            onWidgetOpacityChanged: (value) async => applied.add(value))));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(-100, 0));
    await tester.pumpAndSettle();
    // Saved once, when the drag ended — not on every tick of the drag.
    expect(applied.length, 1);
    expect(applied.first, lessThan(100));
    expect(applied.first, greaterThanOrEqualTo(0));
    await tester.pumpWidget(const SizedBox());
  });
}
