import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/print_job.dart';
import '../theme.dart';
import '../services/cmyk_tiff.dart';
import '../services/designer_photo_thumb.dart';
import '../services/file_preview.dart';
import '../services/upload_rules.dart';
import '../services/color_mode.dart';
import '../services/done_watcher.dart';
import '../services/local_notify.dart';
import '../services/notification_store.dart';
import '../services/job_store.dart';
import '../services/transfer_service.dart';
import '../widgets/designer_avatar.dart';

/// Designer PC screen.
///
/// The designer picks the printer FIRST (Human Y-Jet / Challenger),
/// then the file. The file goes straight to that printer PC — the
/// other printer PC never sees it.
/// One file in the send batch (v1.26). The colour mode is
/// detected once at pick time, so the batch list can show it
/// and the upload loop does not re-read every header.
class _PickedFile {
  const _PickedFile({
    required this.file,
    required this.name,
    required this.size,
    required this.mode,
  });

  final File file;
  final String name;
  final int size;
  final FileColorMode mode;
}

class DesignerScreen extends StatefulWidget {
  const DesignerScreen({
    super.key,
    required this.designerName,
    required this.yJetIp,
    required this.challengerIp,
  });

  /// Designer nam ar printer IP ekhon Profile / Settings-e thake
  /// (gear icon) — upload form-e ar nei.
  final String designerName;
  final String yJetIp;
  final String challengerIp;

  @override
  State<DesignerScreen> createState() => _DesignerScreenState();
}

class _DesignerScreenState extends State<DesignerScreen> {
  PrinterTarget _printer = PrinterTarget.yJet;
  final _noteController = TextEditingController();
  String _material = kMaterials.first;

  /// The batch (v1.26): the designer picks several files at
  /// once and sends them in one go. One file is just a batch
  /// of one — nothing about the single-file flow changed.
  final List<_PickedFile> _picked = <_PickedFile>[];

  bool get _hasPicked => _picked.isNotEmpty;

  /// Any picked file that is a CMYK TIFF (the Black Fix only
  /// applies to those).
  bool get _anyCmyk =>
      _picked.any((p) => p.mode == FileColorMode.cmyk);

  int get _pickedTotalBytes =>
      _picked.fold(0, (sum, p) => sum + p.size);

  /// Human Y-Jet: no K head — black is built as C95 M95 Y95.
  /// Default ON for Y-Jet, hidden for Challenger.
  bool _yJetBlackFix = true;

  bool? _online;
  bool _checking = false;
  bool _uploading = false;
  bool _converting = false;
  double _progress = 0;
  String? _message;

  List<PrintJob> _sent = <PrintJob>[];
  JobStore? _sentStore;

  /// Polls both printer PCs for job statuses.
  Timer? _statusTimer;
  bool _polling = false;

  String get _currentIp =>
      _printer == PrinterTarget.yJet ? widget.yJetIp : widget.challengerIp;

  @override
  void initState() {
    super.initState();
    _loadSent();
    // Check the printers every 15 seconds — when the operator
    // taps Done, the designer is notified within seconds, and
    // the check also runs right after the sent list loads.
    _statusTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _pollStatuses());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  /// Asks both printer PCs which sent jobs are Done now, and
  /// notifies the designer once for each newly finished file.
  Future<void> _pollStatuses() async {
    if (_polling || _sent.isEmpty) return;
    _polling = true;
    try {
      final statuses = <String, JobStatus>{};
      for (final host in [widget.yJetIp, widget.challengerIp]) {
        if (host.isEmpty) continue;
        statuses.addAll(
            await TransferService.fetchStatuses(host: host));
      }
      if (statuses.isEmpty || !mounted) return;
      final newlyDone =
          newlyDoneJobs(sent: _sent, printerStatuses: statuses);
      if (newlyDone.isEmpty) return;
      for (final job in newlyDone) {
        await _sentStore?.updateStatus(job.id, JobStatus.done);
      }
      if (!mounted) return;
      setState(() {
        for (final job in newlyDone) {
          // One entry in the notification center (bell in the top
          // bar) per finished file — the store dedupes by job id.
          NotificationStore.instance.add(job);
          final index = _sent.indexWhere((j) => j.id == job.id);
          if (index != -1) {
            _sent[index] = job.copyWith(status: JobStatus.done);
          }
        }
      });
      // Windows toast (v1.26) — visible even when the app is
      // minimised. Best-effort: the in-app notification above
      // is the one that must never be lost.
      for (final job in newlyDone) {
        unawaited(showDoneNotification(
          designerName: job.designerName,
          fileName: job.fileName,
        ));
      }
      for (final job in newlyDone) {
        if (!mounted) break;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Hey ${widget.designerName}, your design file completely Printing Ready — ${job.fileName}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      _polling = false;
    }
  }

  Future<Directory> _sentDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/Signtech File Sharing/Sent');
  }

  Future<void> _loadSent() async {
    final store = JobStore(await _sentDir());
    final jobs = await store.load();
    if (mounted) {
      setState(() {
        _sentStore = store;
        _sent = jobs;
      });
      _pollStatuses();
    }
  }

  void _selectPrinter(PrinterTarget printer) {
    setState(() {
      _printer = printer;
      _online = null;
    });
  }

  Future<void> _checkOnline() async {
    final host = _currentIp;
    if (host.isEmpty) {
      setState(() => _message =
          'Printer PC IP not set — enter it in Profile (gear icon).');
      return;
    }
    setState(() {
      _checking = true;
      _message = null;
    });
    final ok = await TransferService.ping(host: host);
    if (mounted) {
      setState(() {
        _checking = false;
        _online = ok;
        _message = ok
            ? '${_printer.label} PC online ache.'
            : '${_printer.label} PC not reachable — check the IP and that the app is running on that PC.';
      });
    }
  }

  /// Picks files — several at once (v1.26, suggestion 2).
  /// Each file is checked on its own: good files join the
  /// batch, rejected ones are listed together afterwards
  /// instead of stopping the whole pick.
  Future<void> _pickFile() async {
    // Shop rule: ONLY TIF / JPG / EPS — nothing else.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kAllowedExtensions,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final rejected = <String>[];
    var added = 0;
    for (final picked in result.files) {
      if (picked.path == null) continue;
      // Already in the batch — skip, do not duplicate.
      if (_picked.any((p) => p.file.path == picked.path)) continue;
      if (!isAllowedFileName(picked.name)) {
        rejected.add(
            '${picked.name} — this format is not allowed (only $kAllowedFormatsLabel).');
        continue;
      }
      final file = File(picked.path!);
      final mode = await _detectMode(file, picked.name);
      // Shop rule: CMYK ONLY. RGB / grayscale / CMYK JPG are
      // rejected here with the reason — nothing is picked.
      final decision =
          decidePickedFile(fileName: picked.name, mode: mode);
      if (decision != PickDecision.accept) {
        rejected.add(
            '${picked.name} — ${decision == PickDecision.rejectCmykJpg ? 'CMYK JPG — send a CMYK TIFF instead' : 'only CMYK files can be sent (this one is ${mode.label})'}.');
        continue;
      }
      setState(() {
        _picked.add(_PickedFile(
          file: file,
          name: picked.name,
          size: picked.size,
          mode: mode,
        ));
      });
      added++;
    }
    if (!mounted) return;
    if (rejected.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(added > 0
              ? 'Some files were not added'
              : 'No files added'),
          content: Text(rejected.join('\n')),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    if (mounted && added > 0 && rejected.isEmpty) {
      setState(() => _message = null);
    }
  }

  /// Detects the colour mode from the file header only — no
  /// full decode. A read failure leaves the mode unknown (the
  /// upload rules then decide what to do with it).
  Future<FileColorMode> _detectMode(File file, String name) async {
    try {
      final head = await file
          .openRead(0, 200000)
          .fold<Uint8List>(Uint8List(0),
              (prev, chunk) => Uint8List.fromList([...prev, ...chunk]));
      return detectColorMode(head, name);
    } catch (_) {
      return FileColorMode.unknown;
    }
  }

  /// Sends the whole batch (v1.26), one file after another.
  /// Each file is converted (Y-Jet Black Fix), previewed and
  /// uploaded on its own, so one bad file never stops the rest:
  /// sent files leave the batch, failed ones stay picked with
  /// the reason in the message, ready to retry.
  Future<void> _upload() async {
    final host = _currentIp;
    if (host.isEmpty) {
      setState(() => _message =
          'Printer PC IP not set — enter it in Profile (gear icon).');
      return;
    }
    if (_picked.isEmpty) {
      setState(() => _message = 'Age ekta file beche nao.');
      return;
    }
    final designer = widget.designerName;
    if (designer.isEmpty) {
      setState(() => _message =
          'Your name is not set — enter it in Profile (gear icon).');
      return;
    }
    final files = List<_PickedFile>.from(_picked);
    // The designer's profile photo travels with every file as
    // a small thumbnail (v1.23) — computed once for the batch.
    final photoBase64 = await designerPhotoThumbnailBase64();
    var sent = 0;
    final failed = <String>[];
    setState(() {
      _uploading = true;
      _progress = 0;
      _message = null;
    });
    for (var i = 0; i < files.length; i++) {
      final picked = files[i];
      if (!mounted) break;
      setState(() =>
          _message = 'Sending ${i + 1}/${files.length}: ${picked.name}…');
      try {
        final job = await _sendOne(
          picked,
          photoBase64,
          onFileProgress: (p) {
            if (mounted) {
              setState(() => _progress = (i + p) / files.length);
            }
          },
        );
        await _sentStore?.add(job);
        sent++;
        if (mounted) {
          setState(() => _picked
              .removeWhere((p) => p.file.path == picked.file.path));
        }
      } catch (e) {
        failed.add('${picked.name}: $e');
      } finally {
        if (mounted) {
          setState(() => _progress = (i + 1) / files.length);
        }
      }
    }
    await _loadSent();
    if (mounted) {
      setState(() {
        _uploading = false;
        _progress = 0;
        _message = 'Sent $sent of ${files.length} file${files.length == 1 ? '' : 's'} to ${_printer.label} PC.'
            '${failed.isEmpty ? '' : '\nFailed:\n${failed.join('\n')}'}';
      });
    }
  }

  /// Converts (Y-Jet Black Fix), previews and uploads one file,
  /// and returns the sent job. Throws a plain message on any
  /// failure — the batch loop catches it per file.
  Future<PrintJob> _sendOne(
    _PickedFile picked,
    String? photoBase64, {
    required void Function(double progress) onFileProgress,
  }) async {
    // Human Y-Jet black fix: in a CMYK TIFF, K black is rebuilt
    // from the 3 colour heads (C95 M95 Y95, K0 — no K head on
    // that printer). The file keeps the designer's exact name.
    File sendFile = picked.file;
    String sendName = picked.name;
    int sendSize = picked.size;
    var blackConverted = false;
    var colorModeLabel = picked.mode.label;
    File? tempConverted;
    final ext = picked.name.toLowerCase().split('.').last;
    final canConvert = _printer == PrinterTarget.yJet &&
        _yJetBlackFix &&
        picked.mode == FileColorMode.cmyk &&
        (ext == 'tif' || ext == 'tiff');
    if (canConvert) {
      if (mounted) {
        setState(() {
          _converting = true;
          _message = 'Converting K black to C95 M95 Y95… (${picked.name})';
        });
      }
      try {
        // Streaming conversion: the file is never held whole in
        // memory, so there is no size limit.
        tempConverted =
            File('${Directory.systemTemp.path}/$sendName');
        await convertCmykTiffBlackFile(
            input: picked.file, output: tempConverted);
        sendFile = tempConverted;
        sendSize = await tempConverted.length();
        blackConverted = true;
        colorModeLabel = 'CMYK';
      } catch (e) {
        throw Exception(
            'Conversion failed, so the original file was NOT sent: $e');
      } finally {
        if (mounted) setState(() => _converting = false);
      }
    }

    // A small preview of the design travels with the file
    // (v1.26) so the printer PC shows the picture in the Jobs
    // view. Null for EPS / undecodable files — the upload
    // never waits on the preview.
    final previewBase64 = await designPreviewBase64(
        file: picked.file, fileName: picked.name);

    // Customer / Order / Size / Quantity — total remove (2026-11-13).
    // Model fields stay '' / 1 only so old jobs.json files still load.
    final job = PrintJob(
      id: '${DateTime.now().millisecondsSinceEpoch}_${picked.name.hashCode.abs()}',
      fileName: sendName,
      customerName: '',
      orderNo: '',
      size: '',
      material: _material,
      quantity: 1,
      note: _noteController.text.trim(),
      designerName: widget.designerName,
      printer: _printer,
      status: JobStatus.pending,
      receivedAt: DateTime.now(),
      filePath: sendFile.path,
      fileSizeBytes: sendSize,
      colorMode: colorModeLabel,
      blackConverted: blackConverted,
      originalFileName: blackConverted ? picked.name : '',
      previewBase64: previewBase64,
    );
    try {
      await TransferService.uploadFile(
        host: _currentIp,
        file: sendFile,
        job: job,
        designerPhotoBase64: photoBase64,
        previewBase64: previewBase64,
        onProgress: onFileProgress,
      );
    } finally {
      try {
        await tempConverted?.delete();
      } catch (_) {
        // Temp file cleanup is best-effort only.
      }
    }
    return job;
  }

  // ------------------------------------------------------------------
  //  Professional layout
  //
  //  Wide window (Windows PC): two columns — left = printer +
  //  connection, right = file + send. Narrow: one column.
  //  Top: identity bar — who is sending (avatar + name + IP).
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 760;
        // Narrow (portrait, e.g. the 430px SHAREit-style window):
        // compact controls so the whole form stays short.
        final body = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _printerCard(context)),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: _fileCard(context)),
                ],
              )
            : Column(
                children: [
                  _printerCard(context, compact: true),
                  const SizedBox(height: 10),
                  _fileCard(context, compact: true),
                ],
              );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _identityBar(context, compact: !wide),
                const SizedBox(height: 12),
                body,
                const SizedBox(height: 16),
                _sentSection(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String step, String title) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: SigntechTheme.brandBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(step,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  Widget _identityBar(BuildContext context, {bool compact = false}) {
    final scheme = Theme.of(context).colorScheme;
    final name =
        widget.designerName.isEmpty ? 'Name not set' : widget.designerName;
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: compact ? 8 : 10),
        child: Row(
          children: [
            ProfilePhotoAvatar(
                designerName: widget.designerName,
                size: compact ? 36 : 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    'Designer PC  •  Change name / IP in Profile (gear icon)',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
            DesignerChip(name: widget.designerName.isEmpty ? '—' : widget.designerName),
          ],
        ),
      ),
    );
  }

  Widget _printerCard(BuildContext context, {bool compact = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('1', 'Which printer to send to?'),
            SizedBox(height: compact ? 8 : 10),
            if (compact)
              _compactPrinterPicker(context)
            else
              Row(
                children: PrinterTarget.values.map((p) {
                  final selected = p == _printer;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: p == PrinterTarget.yJet ? 8 : 0,
                          left: p == PrinterTarget.challenger ? 8 : 0),
                      child: InkWell(
                        onTap: () => _selectPrinter(p),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 12),
                          decoration: BoxDecoration(
                            color: selected
                                ? SigntechTheme.brandBlue
                                : scheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? SigntechTheme.brandBlue
                                  : Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.print,
                                size: 28,
                                color: selected
                                    ? Colors.white
                                    : scheme.onSurface,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                p.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? Colors.white
                                      : scheme.onSurface,
                                ),
                              ),
                              Text(
                                selected ? 'Selected' : 'Tap to select',
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white70
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.lan,
                      size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _currentIp.isEmpty
                          ? (compact
                              ? 'IP not set — enter it in Profile.'
                              : '${_printer.label} PC IP not set — enter it in Profile (gear icon).')
                          : '${_printer.label} PC:  $_currentIp',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (_online != null)
                    Icon(
                      _online! ? Icons.check_circle : Icons.error,
                      color: _online! ? Colors.green : Colors.red,
                    ),
                  // Compact: the online check lives in this row as
                  // an icon — the full-width button below is wide-only.
                  if (compact)
                    _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.wifi_find, size: 20),
                            tooltip: 'Is the printer PC online?',
                            onPressed: _checkOnline,
                          ),
                ],
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _checking ? null : _checkOnline,
                  icon: const Icon(Icons.wifi_find, size: 18),
                  label: Text(_checking
                      ? 'Checking…'
                      : 'Is the printer PC online?'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact printer picker for narrow (portrait) windows: a
  /// segmented control instead of the big tiles — same choice,
  /// about half the height.
  Widget _compactPrinterPicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(PrinterTarget target) {
      final selected = target == _printer;
      return Expanded(
        child: InkWell(
          onTap: () => _selectPrinter(target),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? SigntechTheme.brandBlue : scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? SigntechTheme.brandBlue
                    : Theme.of(context).dividerColor,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.print,
                    size: 18,
                    color: selected ? Colors.white : scheme.onSurface),
                const SizedBox(width: 8),
                Text(target.label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : scheme.onSurface)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(PrinterTarget.yJet),
        const SizedBox(width: 8),
        option(PrinterTarget.challenger),
      ],
    );
  }

  Widget _fileCard(BuildContext context, {bool compact = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
                '2',
                compact
                    ? 'File and job details — CMYK TIF / EPS'
                    : 'File and job details'),
            SizedBox(height: compact ? 8 : 10),
            InkWell(
              onTap: _pickFile,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                    vertical: compact ? 10 : 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: SigntechTheme.brandBlue.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: SigntechTheme.brandBlue.withOpacity(0.45),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _picked.isEmpty
                          ? Icons.cloud_upload_outlined
                          : Icons.insert_drive_file,
                      size: compact ? 24 : 30,
                      color: SigntechTheme.brandBlue,
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    Text(
                      _picked.isEmpty
                          ? 'Choose files'
                          : '${_picked.length} file${_picked.length == 1 ? '' : 's'} ready',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    // Compact: the format note lives in the card
                    // title instead — hide this line until files
                    // are picked (then it shows the total size).
                    if (!compact || _picked.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _picked.isEmpty
                            ? 'CMYK files only (TIF / EPS) — pick as many as you like, each file keeps the exact name you send it with'
                            : PrintJob(
                                  id: '',
                                  fileName: '',
                                  customerName: '',
                                  orderNo: '',
                                  size: '',
                                  material: '',
                                  quantity: 1,
                                  note: '',
                                  designerName: '',
                                  printer: _printer,
                                  status: JobStatus.pending,
                                  receivedAt: DateTime.now(),
                                  filePath: '',
                                  fileSizeBytes: _pickedTotalBytes)
                              .sizeLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // The batch, one row per file (v1.26) — tap X to
            // take a file out before sending.
            if (_picked.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._picked.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: p.mode == FileColorMode.cmyk
                                ? Colors.green.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(p.mode.label,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          onPressed: (_uploading || _converting)
                              ? null
                              : () => setState(() => _picked.remove(p)),
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove from batch',
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                  )),
            ],
            if (_picked.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _anyCmyk
                          ? Colors.green.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        'Colour: ${_anyCmyk ? 'CMYK' : _picked.first.mode.label}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (_anyCmyk &&
                      _printer == PrinterTarget.yJet &&
                      _yJetBlackFix)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('→ K black will print as C95 M95 Y95',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant)),
                    ),
                ],
              ),
              if (_anyCmyk) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: Text(
                    _printer == PrinterTarget.yJet && _yJetBlackFix
                        ? 'CMYK file — its black (K) will be rebuilt from 3 colours (C95 M95 Y95) on send, because the Human Y-Jet has no K head.'
                        : 'CMYK file — sent as it is.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ],
            ],
            if (_printer == PrinterTarget.yJet) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Human Y-Jet Black Fix: C95 M95 Y95',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  compact
                      ? 'No K head — K black is rebuilt as C95 M95 Y95.'
                      : 'No K head — K black is rebuilt as C95 M95 Y95. RGB files are not accepted.',
                ),
                value: _yJetBlackFix,
                activeColor: SigntechTheme.brandBlue,
                onChanged: (v) => setState(() => _yJetBlackFix = v),
              ),
            ],
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _material,
              decoration: const InputDecoration(
                labelText: 'Material',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: kMaterials
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _material = v);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            SizedBox(
              height: compact ? 44 : 48,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_uploading || _converting) ? null : _upload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SigntechTheme.brandBlue,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.send),
                label: Text(
                  _converting
                      ? 'Converting… (K black → C95/M95/Y95)'
                      : _uploading
                          ? 'Sending… ${(_progress * 100).toStringAsFixed(0)}%'
                          : _picked.isEmpty
                              ? 'Send file to ${_printer.label}'
                              : _printer == PrinterTarget.yJet &&
                                      _yJetBlackFix &&
                                      _anyCmyk
                                  ? 'Convert black and send ${_picked.length} file${_picked.length == 1 ? '' : 's'} (K → C95/M95/Y95)'
                                  : 'Send ${_picked.length} file${_picked.length == 1 ? '' : 's'} to ${_printer.label}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            if (_uploading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: _progress),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sentSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Sent files',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: SigntechTheme.brandBlue.withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_sent.length}',
                  style: const TextStyle(
                      color: SigntechTheme.brandBlue,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_sent.isEmpty)
          Text('Nothing sent yet.',
              style: TextStyle(color: scheme.onSurfaceVariant))
        else
          ..._sent.map((job) => Card(
                child: ListTile(
                  // The design's own picture when one travelled
                  // with the file (v1.26); otherwise the
                  // designer's photo as before.
                  leading: job.previewBase64 != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            base64Url.decode(job.previewBase64!),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                ProfilePhotoAvatar(
                                    designerName: job.designerName,
                                    size: 40),
                          ),
                        )
                      : ProfilePhotoAvatar(
                          designerName: job.designerName, size: 40),
                  title: Text(job.fileName,
                      style:
                          const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${job.printer.label}  •  ${job.material}  •  ${job.sizeLabel}  •  ${job.colorMode}${job.blackConverted ? '  •  Black C95/M95/Y95' : ''}${job.status == JobStatus.done ? '  •  Printing Ready' : ''}'),
                  trailing: job.status == JobStatus.done
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Printing Ready',
                              style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12)),
                        )
                      : DesignerChip(name: job.designerName),
                ),
              )),
      ],
    );
  }
}
