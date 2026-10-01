import 'package:flutter_test/flutter_test.dart';
import 'package:pcos_frontend/features/transfers/models/transfer_item.dart';
import 'package:pcos_frontend/features/transfers/services/transfer_manager.dart';

void main() {
  group('TransferItem', () {
    test('computes progress correctly', () {
      final item = TransferItem(
        id: 'item_1',
        name: 'test_file.iso',
        type: TransferType.upload,
        sizeBytes: 1000,
        transferredBytes: 500,
      );
      expect(item.progress, 0.5);
      expect(item.formattedSize, '1000 B');
      expect(item.formattedTransferred, '500 B');
    });

    test('formats speed and ETA when in progress', () {
      final item = TransferItem(
        id: 'item_2',
        name: 'video.mp4',
        type: TransferType.download,
        sizeBytes: 10485760, // 10 MB
        transferredBytes: 5242880, // 5 MB
        status: TransferStatus.inProgress,
        speedBps: 1048576, // 1 MB/s
        etaSeconds: 5,
      );
      expect(item.formattedSpeed, '1.0 MB/s');
      expect(item.formattedEta, '5s remaining');
    });
  });

  group('TransferManager', () {
    late TransferManager manager;

    setUp(() {
      manager = TransferManager();
      manager.clearAll();
    });

    test('adds transfer and tracks active count', () {
      final item = manager.createTransfer(
        name: 'large_dataset.tar.gz',
        type: TransferType.upload,
        sizeBytes: 50000000,
      );

      expect(manager.items.length, 1);
      expect(manager.items.first.id, item.id);
      expect(manager.activeCount, 1);
      expect(item.status, TransferStatus.inProgress);
    });

    test('pause, resume, and cancel transfers', () {
      final item = manager.createTransfer(
        name: 'backup_archive.zip',
        type: TransferType.backup,
        sizeBytes: 20000000,
      );

      manager.pauseTransfer(item.id);
      expect(item.status, TransferStatus.paused);
      expect(manager.activeCount, 0);

      manager.resumeTransfer(item.id);
      expect(item.status, TransferStatus.inProgress);
      expect(manager.activeCount, 1);

      manager.cancelTransfer(item.id);
      expect(item.status, TransferStatus.cancelled);
      expect(manager.activeCount, 0);
    });

    test('markCompleted and clearCompleted lifecycle', () {
      final item = manager.createTransfer(
        name: 'transcoded_stream.m3u8',
        type: TransferType.transcode,
        sizeBytes: 1000,
      );

      manager.markCompleted(item.id);
      expect(item.status, TransferStatus.completed);
      expect(item.transferredBytes, 1000);
      expect(manager.activeCount, 0);

      manager.clearCompleted();
      expect(manager.items.isEmpty, true);
    });

    test('supports bandwidth limit setting', () {
      manager.bandwidthLimit = 5 * 1024 * 1024;
      expect(manager.bandwidthLimit, 5 * 1024 * 1024);

      manager.bandwidthLimit = null;
      expect(manager.bandwidthLimit, isNull);
    });
  });
}
