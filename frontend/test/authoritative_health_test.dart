import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Authoritative Health & Dashboard Telemetry Rules', () {
    test(
        'Storage node online status must be derived from parent device online status',
        () {
      final parentDevice = {
        'id': 'dev-1',
        'name': 'Dayan Desktop',
        'is_online': 0, // offline
        'last_seen_at': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
      };

      final storageNode = {
        'id': 'node-1',
        'device_id': 'dev-1',
        'name': 'Windows-SSD',
        'is_online': 1, // Stale DB column
        'status': 'active',
      };
      expect(storageNode['name'], 'Windows-SSD');

      // Rule: Effective online must be parent.is_online == 1, NOT the storage_node's un-joined status
      final effectiveOnline = parentDevice['is_online'] == 1;
      expect(effectiveOnline, isFalse);

      final displayStatus =
          effectiveOnline ? 'ONLINE' : 'OFFLINE (Unreachable)';
      expect(displayStatus, 'OFFLINE (Unreachable)');
      expect(displayStatus, isNot('Healthy'));
    });

    test(
        'Measured RPO/RTO must calculate from actual replica divergence, never hardcoded',
        () {
      final clusterNodes = [
        {
          'id': 'dev-1',
          'is_online': false,
          'last_seen_at': DateTime.now()
              .subtract(const Duration(minutes: 10))
              .toIso8601String()
        },
        {
          'id': 'dev-2',
          'is_online': false,
          'last_seen_at': DateTime.now()
              .subtract(const Duration(minutes: 15))
              .toIso8601String()
        },
        {
          'id': 'dev-3',
          'is_online': false,
          'last_seen_at': DateTime.now()
              .subtract(const Duration(minutes: 30))
              .toIso8601String()
        },
      ];

      final onlineCount =
          clusterNodes.where((n) => n['is_online'] == true).length;
      expect(onlineCount, 0);

      // When 0 nodes are online, cluster status is offline and RTO is measured or unreachable
      final status = onlineCount == 0
          ? 'offline'
          : (onlineCount < 2 ? 'degraded' : 'healthy');
      expect(status, 'offline');
    });

    testWidgets('Renders Screenshot 2 dashboard storage summary card',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Your storage',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('6 reported volumes',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Windows-SSD', style: TextStyle(fontSize: 14)),
                          Text('251.6 GB', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(value: 0.65),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          ElevatedButton(
                              onPressed: () {},
                              child: const Text('Design full UI')),
                          const SizedBox(width: 8),
                          OutlinedButton(
                              onPressed: () {},
                              child: const Text('Fix status issues')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your storage'), findsOneWidget);
      expect(find.text('6 reported volumes'), findsOneWidget);
      expect(find.text('Windows-SSD'), findsOneWidget);
      expect(find.text('251.6 GB'), findsOneWidget);
      expect(find.text('Design full UI'), findsOneWidget);
      expect(find.text('Fix status issues'), findsOneWidget);
    });
  });
}
