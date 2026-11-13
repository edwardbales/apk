import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/print_job.dart';
import '../theme.dart';
import 'designer_avatar.dart';

/// "13 Nov 2026, 5:41 PM" — the full sent time, for the Jobs
/// detail view. The dashboard cards keep the short "17:41, 13/11".
String formatJobTimeFull(DateTime t) {
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = t.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, '
      '$hour12:$mm $ampm';
}

/// One job, fully opened up — the Jobs view (v1.23).
///
/// Everything the operator asked for, in one card: the designer's
/// photo (or initials when the job has no photo), the designer
/// name, the file that was sent, when it was sent, and the design
/// details (material, file size, colour mode, black fix, note) —
/// plus the same Printing / Done / Forward actions as the
/// dashboard cards.
class JobDetailCard extends StatelessWidget {
  const JobDetailCard({
    super.key,
    required this.job,
    required this.narrow,
    required this.otherPrinterLabel,
    required this.onSetStatus,
    required this.onForward,
    this.onOpenInRip,
  });

  final PrintJob job;
  final bool narrow;
  final String otherPrinterLabel;
  final void Function(PrintJob job, JobStatus status) onSetStatus;
  final void Function(PrintJob job) onForward;

  /// Opens the file in the saved RIP program (v1.26). Null when
  /// the screen does not offer it — the button is then hidden.
  final void Function(PrintJob job)? onOpenInRip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = job.status == JobStatus.done
        ? Colors.green
        : job.status == JobStatus.printing
            ? Colors.blue
            : Colors.orange;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(job.status.label,
          style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w800,
              fontSize: 12)),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                JobDesignerAvatar(
                  name: job.designerName,
                  photoBase64: job.designerPhotoBase64,
                  size: narrow ? 48 : 56,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.designerName.isEmpty
                            ? 'Unknown designer'
                            : job.designerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: narrow ? 15 : 17,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sent: ${formatJobTimeFull(job.receivedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (onOpenInRip != null)
                  IconButton(
                    onPressed: () => onOpenInRip!(job),
                    icon: const Icon(Icons.open_in_new, size: 20),
                    tooltip: 'Open in RIP',
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                if (!narrow) pill,
              ],
            ),
            if (narrow) ...[
              const SizedBox(height: 8),
              pill,
            ],
            // The design itself (v1.26) — the operator sees what
            // the file is before opening RIP. EPS jobs and old
            // jobs have no preview and show no picture.
            if (job.previewBase64 != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  // The server validated this JPEG on upload, so
                  // the decode here cannot fail in practice; the
                  // errorBuilder is a belt-and-braces guard.
                  base64Url.decode(job.previewBase64!),
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _detailRow(context, 'File', job.fileName),
                  if (job.originalFileName.isNotEmpty)
                    _detailRow(
                        context, 'Original file', job.originalFileName),
                  _detailRow(context, 'Material', job.material),
                  _detailRow(context, 'File size', job.sizeLabel),
                  _detailRow(context, 'Colour', job.colorMode),
                  _detailRow(
                    context,
                    'Black fix',
                    job.blackConverted
                        ? 'C95 M95 Y95 (3-color black)'
                        : 'Not converted',
                  ),
                  if (job.note.isNotEmpty)
                    _detailRow(context, 'Note', job.note),
                ],
              ),
            ),
            const SizedBox(height: 12),
            narrow
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: job.status == JobStatus.printing
                            ? null
                            : () => onSetStatus(job, JobStatus.printing),
                        child: const Text('Printing'),
                      ),
                      OutlinedButton(
                        onPressed: job.status == JobStatus.done
                            ? null
                            : () => onSetStatus(job, JobStatus.done),
                        child: const Text('Done'),
                      ),
                      TextButton.icon(
                        onPressed: () => onForward(job),
                        icon: const Icon(Icons.send, size: 16),
                        label: const Text('Forward'),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      OutlinedButton(
                        onPressed: job.status == JobStatus.printing
                            ? null
                            : () => onSetStatus(job, JobStatus.printing),
                        child: const Text('Printing'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: job.status == JobStatus.done
                            ? null
                            : () => onSetStatus(job, JobStatus.done),
                        child: const Text('Done'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => onForward(job),
                        icon: const Icon(Icons.send, size: 16),
                        label: Text('Send to $otherPrinterLabel'),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
