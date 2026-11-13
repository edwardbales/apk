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

  Future<void> load({Directory? documentsDir}) async {
    _documentsDir =
        documentsDir ?? await getApplicationDocumentsDirectory();
    try {
      if (!await _file.exists()) return;
      final raw = await _file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(decoded.map(
            (e) => DoneNotification.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    } catch (_) {
      // Corrupt file: start empty, like v1.9 did.
    }
  }

  Future<void> _save() async {
    if (_documentsDir == null) return;
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
          jsonEncode(_items.map((n) => n.toJson()).toList()));
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
