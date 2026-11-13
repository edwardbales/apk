import '../models/print_job.dart';

/// Finds the sent jobs that just became Done on a printer PC.
///
/// A job counts as newly done when the printer reports its status
/// as done AND the designer's own copy still says something else
/// (pending / printing). Once the designer marks its copy done,
/// it is never reported again — so one Done click = one
/// notification, even if the app restarts and polls again.
List<PrintJob> newlyDoneJobs({
  required List<PrintJob> sent,
  required Map<String, JobStatus> printerStatuses,
}) {
  return sent.where((job) {
    return printerStatuses[job.id] == JobStatus.done &&
        job.status != JobStatus.done;
  }).toList();
}
