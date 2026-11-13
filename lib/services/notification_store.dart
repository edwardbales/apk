import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/print_job.dart';

/// One "Printing Ready" notification for the designer.
class DoneNotification {
  DoneNotification({
    required this.job,
    required this.notifiedAt,
    this.read = false,
  });

  final PrintJob job;
  final DateTime notifiedAt;
  bool read;

  Map<String, dynamic> toJson() => {
        'job': job.toJson(),
        'notifiedAt': notifiedAt.toIso8601String(),
        'read': read,
      };

  factory DoneNotification.fromJson(Map<String, dynamic> json) {
    return DoneNotification(
      job: PrintJob.fromJson(json['job'] as Map<String, dynamic>),
      notifiedAt: DateTime.tryParse(json['notifiedAt'] as String? ?? '') ??
          DateTime.now(),
      read: json['read'] as bool? ?? false,
    );
  }
}

/// The designer's notification center.
///
/// The bell in the top bar listens to this store. Notifications are
/// saved to Documents/Signtech File Sharing/Sent/notifications.json
/// so they survive an app restart — the badge count stays real.
class NotificationStore extends ChangeNotifier {
  NotificationStore();

  static final NotificationStore instance = NotificationStore();

  final List<DoneNotification> _items = <DoneNotification>[];
  Directory? _documentsDir;

  List<DoneNotification> get items => List.unmodifiable(_items);

  int get unreadCount => _items.where((n) => !n.read).length;

  bool get hasUnread => unreadCount > 0;

  File get _file => File(
      '${_documentsDir!.path}/Signtech File Sharing/Sent/notifications.json');

  File get _backupFile => File(
      '${_documentsDir!.path}/Signtech File Sharing/Sent/notifications.json.bak');

  Future<void> load({Directory? documentsDir}) async {
    _documentsDir =
        documentsDir ?? await getApplicationDocumentsDirectory();
    // Reads notifications.json, falling back to the previous
    // good copy when it is damaged (v1.26.1, same power-cut
    // proofing as JobStore). Both missing or damaged means an
    // empty list, like v1.9 did.
    for (final file in [_file, _backupFile]) {
      try {
        if (!await file.exists()) continue;
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as List<dynamic>;
        _items
          ..clear()
          ..addAll(decoded.map(
              (e) => DoneNotification.fromJson(e as Map<String, dynamic>)));
        notifyListeners();
        return;
      } catch (_) {
        continue; // damaged — try the backup
      }
    }
  }

  Future<void> _save() async {
    if (_documentsDir == null) return;
    try {
      await _file.parent.create(recursive: true);
      // Atomic save (v1.26.1): temp file + rename, with the
      // previous good copy kept as .bak — a power cut mid-save
      // can never leave a half-written notifications file.
      final raw = jsonEncode(_items.map((n) => n.toJson()).toList());
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(raw, flush: true);
      try {
        if (await _file.exists()) await _file.copy(_backupFile.path);
      } catch (_) {}
      try {
        await tmp.rename(_file.path);
      } catch (_) {
        try {
          await _file.delete();
        } catch (_) {}
        await tmp.rename(_file.path);
      }
    } catch (_) {
      // Saving is best-effort; the in-memory list still works.
    }
  }

  /// Adds a notification for [job] — once per job only.
  Future<void> add(PrintJob job) async {
    if (_items.any((n) => n.job.id == job.id)) return;
    _items.insert(
        0, DoneNotification(job: job, notifiedAt: DateTime.now()));
    notifyListeners();
    await _save();
  }

  Future<void> markAllRead() async {
    var changed = false;
    for (final n in _items) {
      if (!n.read) {
        n.read = true;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _save();
    }
  }

  Future<void> dismiss(String jobId) async {
    _items.removeWhere((n) => n.job.id == jobId);
    notifyListeners();
    await _save();
  }

  Future<void> clearAll() async {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    await _save();
  }
}
