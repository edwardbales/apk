import 'dart:convert';
import 'dart:io';

import '../models/print_job.dart';

/// Persists the job list as jobs.json next to the received files.
///
/// The printer PC is the source of truth for its own jobs; the
/// Designer PC keeps its own sent-jobs list in the same format.
class JobStore {
  JobStore(this.directory);

  final Directory directory;

  File get _file => File('${directory.path}/jobs.json');

  /// The previous good copy of the list — the fallback when
  /// jobs.json itself is damaged (v1.26.1, power-cut proofing).
  File get _backupFile => File('${directory.path}/jobs.json.bak');

  Future<List<PrintJob>> load() async {
    final jobs = await _tryLoad(_file);
    if (jobs != null) return jobs;
    // jobs.json is damaged — load the previous good copy
    // instead of showing an empty list.
    final backup = await _tryLoad(_backupFile);
    if (backup != null) return backup;
    return <PrintJob>[];
  }

  /// Loads one list file, or null when it is missing or damaged.
  Future<List<PrintJob>?> _tryLoad(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => PrintJob.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Atomic save (v1.26.1): the new list is written to a temp
  /// file first, then renamed over jobs.json — a rename is one
  /// filesystem step, so a power cut can only ever leave the
  /// old jobs.json or the new one, never a half-written file.
  /// The previous good list is kept as jobs.json.bak, so even
  /// a damaged jobs.json still loads from the backup.
  Future<void> save(List<PrintJob> jobs) async {
    await directory.create(recursive: true);
    final raw = jsonEncode(jobs.map((j) => j.toJson()).toList());
    final tmp = File('${directory.path}/jobs.json.tmp');
    await tmp.writeAsString(raw, flush: true);
    try {
      if (await _file.exists()) {
        await _file.copy(_backupFile.path);
      }
    } catch (_) {
      // A missing backup never blocks the save.
    }
    try {
      await tmp.rename(_file.path);
    } catch (_) {
      // Some Windows setups refuse to rename over an existing
      // file — delete it first, then rename the temp into
      // place. (If the power dies in between, the .bak above
      // still holds the previous list.)
      try {
        await _file.delete();
      } catch (_) {}
      await tmp.rename(_file.path);
    }
  }

  Future<void> add(PrintJob job) async {
    final jobs = await load();
    jobs.insert(0, job);
    await save(jobs);
  }

  Future<void> updateStatus(String id, JobStatus status) async {
    final jobs = await load();
    final index = jobs.indexWhere((j) => j.id == id);
    if (index == -1) return;
    jobs[index] = jobs[index].copyWith(status: status);
    await save(jobs);
  }

  /// Removes finished jobs (Done + Forwarded) from the list and
  /// returns how many were removed. The FILES stay on disk in
  /// their job folders / the OK folder — only the list entries
  /// are cleared (v1.25, Complete-section Clear button).
  Future<int> clearCompleted() async {
    final jobs = await load();
    final kept = jobs
        .where((j) =>
            j.status != JobStatus.done && j.status != JobStatus.forwarded)
        .toList();
    final removed = jobs.length - kept.length;
    if (removed > 0) await save(kept);
    return removed;
  }
}
