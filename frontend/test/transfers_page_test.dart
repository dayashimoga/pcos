import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcos_frontend/features/transfers/models/transfer_item.dart';
import 'package:pcos_frontend/features/transfers/pages/transfers_page.dart';
import 'package:pcos_frontend/features/transfers/services/transfer_manager.dart';

void main() {
  group('TransfersPage Widget Tests', () {
    late TransferManager manager;

    setUp(() {
      manager = TransferManager();
      manager.clearAll();
    });

    testWidgets('renders empty state when no transfers exist', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TransfersPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('No active transfers'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Active'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Completed'), findsOneWidget);
    });

    testWidgets('renders active transfer item with progress', (tester) async {
      manager.createTransfer(
        name: '4k_drone_footage.mp4',
        type: TransferType.upload,
        sizeBytes: 100000000,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: TransfersPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('4k_drone_footage.mp4'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('renders responsively without overflow on 320px mobile viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      manager.createTransfer(
        name: 'backup_2026.tar.gz',
        type: TransferType.backup,
        sizeBytes: 50000000,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: TransfersPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('backup_2026.tar.gz'), findsOneWidget);
    });
  });
}
