import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pcos_frontend/core/theme/theme_service.dart';

void main() {
  group('ThemeService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ThemeService.themeNotifier.value = ThemeMode.dark;
    });

    test('initializes default to dark when no preference is saved', () async {
      await ThemeService.initialize();
      expect(ThemeService.themeNotifier.value, ThemeMode.dark);
    });

    test('sets and persists light mode', () async {
      await ThemeService.setMode(ThemeMode.light);
      expect(ThemeService.themeNotifier.value, ThemeMode.light);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pcos_theme_mode'), 'light');
    });

    test('toggles between dark and light modes', () async {
      ThemeService.themeNotifier.value = ThemeMode.dark;
      await ThemeService.toggle();
      expect(ThemeService.themeNotifier.value, ThemeMode.light);

      await ThemeService.toggle();
      expect(ThemeService.themeNotifier.value, ThemeMode.dark);
    });

    testWidgets('renders ThemeSwitchWidget and toggles theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: const Scaffold(
            body: Center(
              child: ThemeSwitchWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(ThemeService.themeNotifier.value, ThemeMode.light);
    });
  });
}
