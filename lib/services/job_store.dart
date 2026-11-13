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

  Future<List<PrintJob>> load() async {
    try {
      if (!await _file.exists()) return <PrintJob>[];
      final raw = await _file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => PrintJob.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <PrintJob>[];
    }
  }

  Future<void> save(List<PrintJob> jobs) async {
    await directory.create(recursive: true);
    final raw = jsonEncode(jobs.map((j) => j.toJson()).toList());
    await _file.writeAsString(raw);
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
}
