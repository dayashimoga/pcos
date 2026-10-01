import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/transfer_item.dart';

class TransferManager extends ChangeNotifier {
  static final TransferManager _instance = TransferManager._internal();
  factory TransferManager() => _instance;
  TransferManager._internal();

  final List<TransferItem> _items = [];
  final Map<String, int> _lastTransferred = {};
  final Map<String, DateTime> _lastTime = {};

  int? _bandwidthLimitBytesPerSec;

  List<TransferItem> get items => List.unmodifiable(_items);

  int? get bandwidthLimit => _bandwidthLimitBytesPerSec;
  set bandwidthLimit(int? limit) {
    _bandwidthLimitBytesPerSec = limit;
    notifyListeners();
  }

  int get activeCount => _items
      .where((i) =>
          i.status == TransferStatus.inProgress ||
          i.status == TransferStatus.queued)
      .length;

  double get aggregatedSpeedBps => _items
      .where((i) => i.status == TransferStatus.inProgress)
      .fold(0.0, (acc, item) => acc + item.speedBps);

  String get formattedAggregatedSpeed {
    final speed = aggregatedSpeedBps;
    if (speed <= 0) return '0 B/s';
    return '${TransferItem.formatBytes(speed.toInt())}/s';
  }

  TransferItem createTransfer({
    required String name,
    required TransferType type,
    required int sizeBytes,
    CancelToken? cancelToken,
    TransferPriority priority = TransferPriority.normal,
  }) {
    final item = TransferItem(
      id: '${DateTime.now().microsecondsSinceEpoch}_${name.hashCode}',
      name: name,
      type: type,
      sizeBytes: sizeBytes,
      cancelToken: cancelToken,
      priority: priority,
      status: TransferStatus.inProgress,
    );
    _items.insert(0, item);
    _lastTransferred[item.id] = 0;
    _lastTime[item.id] = DateTime.now();
    notifyListeners();
    return item;
  }

  void updateProgress(String id, int transferred, int total) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;

    final item = _items[idx];
    if (item.status != TransferStatus.inProgress) return;

    final now = DateTime.now();
    final prevTime = _lastTime[id] ?? now;
    final prevTransferred = _lastTransferred[id] ?? 0;
    final elapsedMs = now.difference(prevTime).inMilliseconds;

    if (elapsedMs >= 500) {
      final deltaBytes = transferred - prevTransferred;
      final speed = deltaBytes > 0 ? (deltaBytes / (elapsedMs / 1000.0)) : 0.0;
      item.speedBps = speed;

      final remainingBytes = total - transferred;
      if (speed > 0 && remainingBytes > 0) {
        item.etaSeconds = (remainingBytes / speed).ceil();
      } else {
        item.etaSeconds = null;
      }

      _lastTime[id] = now;
      _lastTransferred[id] = transferred;
    }

    item.transferredBytes = transferred;
    notifyListeners();
  }

  void markCompleted(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    item.status = TransferStatus.completed;
    item.transferredBytes = item.sizeBytes;
    item.finishedAt = DateTime.now();
    item.speedBps = 0.0;
    item.etaSeconds = null;
    _lastTransferred.remove(id);
    _lastTime.remove(id);
    notifyListeners();
  }

  void markFailed(String id, String error) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    item.status = TransferStatus.failed;
    item.error = error;
    item.speedBps = 0.0;
    item.etaSeconds = null;
    _lastTransferred.remove(id);
    _lastTime.remove(id);
    notifyListeners();
  }

  void pauseTransfer(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    if (item.status == TransferStatus.inProgress) {
      item.status = TransferStatus.paused;
      item.speedBps = 0.0;
      item.etaSeconds = null;
      notifyListeners();
    }
  }

  void resumeTransfer(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    if (item.status == TransferStatus.paused) {
      item.status = TransferStatus.inProgress;
      _lastTime[id] = DateTime.now();
      _lastTransferred[id] = item.transferredBytes;
      notifyListeners();
    }
  }

  void cancelTransfer(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    item.cancelToken?.cancel('Cancelled by user');
    item.status = TransferStatus.cancelled;
    item.speedBps = 0.0;
    item.etaSeconds = null;
    _lastTransferred.remove(id);
    _lastTime.remove(id);
    notifyListeners();
  }

  void retryTransfer(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    item.status = TransferStatus.inProgress;
    item.error = null;
    item.transferredBytes = 0;
    _lastTime[id] = DateTime.now();
    _lastTransferred[id] = 0;
    notifyListeners();
  }

  void pauseAll() {
    for (final item in _items) {
      if (item.status == TransferStatus.inProgress) {
        item.status = TransferStatus.paused;
        item.speedBps = 0.0;
        item.etaSeconds = null;
      }
    }
    notifyListeners();
  }

  void resumeAll() {
    for (final item in _items) {
      if (item.status == TransferStatus.paused) {
        item.status = TransferStatus.inProgress;
        _lastTime[item.id] = DateTime.now();
        _lastTransferred[item.id] = item.transferredBytes;
      }
    }
    notifyListeners();
  }

  void clearCompleted() {
    _items.removeWhere((i) =>
        i.status == TransferStatus.completed ||
        i.status == TransferStatus.cancelled);
    notifyListeners();
  }

  void clearAll() {
    _items.clear();
    _lastTransferred.clear();
    _lastTime.clear();
    notifyListeners();
  }
}
