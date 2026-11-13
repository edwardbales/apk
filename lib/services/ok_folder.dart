import '../models/print_job.dart';

/// The OK folder inside the printer's RIP (incoming) folder.
///
/// The operator prints a file in RIP, then moves the printed file
/// into the OK folder. The printer PC watches that folder and
/// marks the matching job Done automatically — the designer then
/// gets the "Printing Ready" notification through the normal
/// status poll, with no click needed on the printer PC.
///
/// Matching is by exact file name. One OK file marks one job:
/// the oldest job with that name that is not Done yet (and not
/// forwarded to the other printer — that file lives there now).
PrintJob? findJobForOkFile({
  required List<PrintJob> jobs,
  required String fileName,
}) {
  final matches = jobs.where((job) =>
      job.fileName == fileName &&
      job.status != JobStatus.done &&
      job.status != JobStatus.forwarded);
  if (matches.isEmpty) return null;
  final sorted = matches.toList()
    ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  return sorted.first;
}
