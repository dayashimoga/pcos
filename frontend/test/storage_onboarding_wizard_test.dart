import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pcos_frontend/core/di/service_locator.dart';
import 'package:pcos_frontend/core/network/api_client.dart';
import 'package:pcos_frontend/features/storage/widgets/storage_onboarding_wizard.dart';

void main() {
  group('Storage Onboarding Wizard & Allowlist Model Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      if (!getIt.isRegistered<SharedPreferences>()) {
        getIt.registerSingleton<SharedPreferences>(prefs);
      }
      if (!getIt.isRegistered<ApiClient>()) {
        getIt.registerLazySingleton<ApiClient>(() => ApiClient(prefs: prefs));
      }
    });

    test(
        'DiscoveredStorageVolume model correctly defaults to denied and serializes',
        () {
      final vol = DiscoveredStorageVolume(
        volumeUuid: 'VOL-TEST-001',
        mountPoint: 'D:\\',
        name: 'Data Volume',
        fsType: 'NTFS',
        totalCapacityBytes: 200 * 1024 * 1024 * 1024,
        availableCapacityBytes: 150 * 1024 * 1024 * 1024,
        isSystemDrive: false,
        isAllowed: false,
      );

      expect(vol.isAllowed, isFalse);
      expect(vol.isSystemDrive, isFalse);

      final json = vol.toJson();
      expect(json['volume_uuid'], 'VOL-TEST-001');
      expect(json['mount_point'], 'D:\\');
      expect(json['is_allowed'], isFalse);
      expect(json['fs_type'], 'NTFS');
    });

    testWidgets(
        'renders initial Pairing Step with OS choices and token generation',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: StorageOnboardingWizard(),
          ),
        ),
      );
      await tester.pump();

      // Verify Header & Step
      expect(find.text('Storage Node Onboarding Wizard'), findsOneWidget);
      expect(find.text('Step 1: Identify your Host Computer or NAS'),
          findsOneWidget);

      // Verify Operating System choices
      expect(find.text('Windows'), findsOneWidget);
      expect(find.text('macOS'), findsOneWidget);
      expect(find.text('Linux'), findsOneWidget);
      expect(find.text('TrueNAS / NAS'), findsOneWidget);

      // Verify Next action button
      expect(find.text('Generate Pairing Code'), findsOneWidget);
    });

    testWidgets(
        'navigates through steps to Volume Selection matching Screenshot 1 specifications',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: StorageOnboardingWizard(),
          ),
        ),
      );
      await tester.pump();

      // Step 0 -> Step 1 (Install Agent)
      final step0Btn = find.text('Generate Pairing Code');
      expect(step0Btn, findsOneWidget);
      await tester.tap(step0Btn);
      await tester.pump(const Duration(milliseconds: 100));

      // Step 1: Install Agent -> Step 2 (Discover Drives)
      expect(find.text('Step 2: Install and Pair the PCOS Node Agent'),
          findsOneWidget);
      final step1Btn = find.text('Next');
      expect(step1Btn, findsOneWidget);
      await tester.tap(step1Btn);
      await tester.pump(const Duration(milliseconds: 100));

      // Step 2: Discover Drives -> Step 3 (Allowlist Configuration - Screenshot 1)
      expect(find.text('Step 3: Discovered Physical Drives'), findsOneWidget);
      final step2Btn = find.text('Next');
      expect(step2Btn, findsOneWidget);
      await tester.tap(step2Btn);
      await tester.pump(const Duration(milliseconds: 100));

      // Step 3: Configure Allowed Storage (Matching Screenshot 1 exactly)
      expect(find.text('Configure allowed storage'), findsOneWidget);
      expect(
        find.text(
            'Illustrative configuration — not connected to your actual disks'),
        findsOneWidget,
      );

      // Verify System SSD is detected & protected
      expect(find.text('C: — System SSD'), findsWidgets);
      expect(find.text('251.6 GB · System drive'), findsWidgets);

      // Verify data volumes from Screenshot 1
      expect(find.text('D: — Data Volume'), findsWidgets);
      expect(find.text('E: — Media Volume'), findsWidgets);
      expect(find.text('F: — Backup Volume'), findsWidgets);

      // Verify "Copy example policy" button from Screenshot 1
      expect(find.text('Copy example policy'), findsOneWidget);

      // Verify security disclaimer from Screenshot 1
      expect(
        find.text(
          'Production PCOS must use stable volume IDs and scoped folder grants, not just drive letters. Changing an allowlist must not silently delete or strand existing files.',
        ),
        findsOneWidget,
      );

      // Verify Selected volumes counter
      expect(find.text('Selected volumes'), findsOneWidget);
    });
  });
}
