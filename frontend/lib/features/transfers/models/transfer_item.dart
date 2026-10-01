import 'package:dio/dio.dart';

enum TransferType {
  upload,
  download,
  sync,
  backup,
  transcode,
}

enum TransferStatus {
  queued,
  inProgress,
  paused,
  completed,
  failed,
  cancelled,
}

enum TransferPriority {
  low,
  normal,
  high,
}

class TransferItem {
  final String id;
  final String name;
  final TransferType type;
  final int sizeBytes;
  int transferredBytes;
  TransferStatus status;
  TransferPriority priority;
  double speedBps;
  int? etaSeconds;
  String? error;
  final DateTime startedAt;
  DateTime? finishedAt;
  CancelToken? cancelToken;

  TransferItem({
    required this.id,
    required this.name,
    required this.type,
    required this.sizeBytes,
    this.transferredBytes = 0,
    this.status = TransferStatus.queued,
    this.priority = TransferPriority.normal,
    this.speedBps = 0.0,
    this.etaSeconds,
    this.error,
    DateTime? startedAt,
    this.finishedAt,
    this.cancelToken,
  }) : startedAt = startedAt ?? DateTime.now();

  double get progress {
    if (sizeBytes <= 0) return status == TransferStatus.completed ? 1.0 : 0.0;
    return (transferredBytes / sizeBytes).clamp(0.0, 1.0);
  }

  String get formattedSize => formatBytes(sizeBytes);
  String get formattedTransferred => formatBytes(transferredBytes);

  String get formattedSpeed {
    if (status != TransferStatus.inProgress || speedBps <= 0) return '';
    return '${formatBytes(speedBps.toInt())}/s';
  }

  String get formattedEta {
    if (status != TransferStatus.inProgress || etaSeconds == null || etaSeconds! <= 0) {
      return '';
    }
    if (etaSeconds! < 60) return '${etaSeconds}s remaining';
    final mins = etaSeconds! ~/ 60;
    final secs = etaSeconds! % 60;
    return '${mins}m ${secs}s remaining';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(d >= 100 || i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}
