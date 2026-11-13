import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/print_job.dart';
import '../theme.dart';
import '../services/cmyk_tiff.dart';
import '../services/upload_rules.dart';
import '../services/color_mode.dart';
import '../services/done_watcher.dart';
import '../services/notification_store.dart';
import '../services/job_store.dart';
import '../services/transfer_service.dart';
import '../widgets/designer_avatar.dart';

/// Designer PC screen.
///
/// The designer picks the printer FIRST (Human Y-Jet / Challenger),
/// then the file. The file goes straight to that printer PC — the
/// other printer PC never sees it.
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

  File? _pickedFile;
  String? _pickedName;
  int _pickedSize = 0;
  FileColorMode _colorMode = FileColorMode.unknown;

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

  Future<void> _pickFile() async {
    // Shop rule: ONLY TIF / JPG / EPS — nothing else.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kAllowedExtensions,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final picked = result.files.first;
    if (picked.path == null) {
      return;
    }
    if (!isAllowedFileName(picked.name)) {
      setState(() => _message =
          'This format is not allowed — only $kAllowedFormatsLabel files can be sent.');
      return;
    }
    final file = File(picked.path!);
    // Detect colour mode from the header only — no full decode.
    var mode = FileColorMode.unknown;
    try {
      final head = await file
          .openRead(0, 200000)
          .fold<Uint8List>(Uint8List(0),
              (prev, chunk) => Uint8List.fromList([...prev, ...chunk]));
      mode = detectColorMode(head, picked.name);
    } catch (_) {
      mode = FileColorMode.unknown;
    }
    // Shop rule: CMYK ONLY. RGB / grayscale / CMYK JPG are
    // rejected here with the reason — nothing is picked.
    final decision =
        decidePickedFile(fileName: picked.name, mode: mode);
    if (decision != PickDecision.accept) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(decision == PickDecision.rejectCmykJpg
                ? 'CMYK JPG — send a CMYK TIFF'
                : 'RGB file — not supported'),
            content: Text(decision == PickDecision.rejectCmykJpg
                ? 'This is a CMYK JPG. Its black (K) cannot be rebuilt as 3-colour black — send a CMYK TIFF instead (Photoshop / Illustrator: export as TIFF, CMYK).'
                : 'Only CMYK files can be sent. This file is ${mode.label} — export a CMYK TIFF from Photoshop / Illustrator and send that.'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }
    setState(() {
      _pickedFile = file;
      _pickedName = picked.name;
      _pickedSize = picked.size;
      _colorMode = mode;
      _message = null;
    });
  }

  Future<void> _upload() async {
    final host = _currentIp;
    final file = _pickedFile;
    if (host.isEmpty) {
      setState(() => _message =
          'Printer PC IP not set — enter it in Profile (gear icon).');
      return;
    }
    if (file == null || _pickedName == null) {
      setState(() => _message = 'Age ekta file beche nao.');
      return;
    }
    final designer = widget.designerName;
    if (designer.isEmpty) {
      setState(() => _message =
          'Your name is not set — enter it in Profile (gear icon).');
      return;
    }

    // Human Y-Jet black fix: in a CMYK TIFF, K black is rebuilt
    // from the 3 colour heads (C95 M95 Y95, K0 — no K head on
    // that printer). The file keeps the designer's exact name.
    File sendFile = file;
    String sendName = _pickedName!;
    int sendSize = _pickedSize;
    var blackConverted = false;
    var colorModeLabel = _colorMode.label;
    File? tempConverted;
    final ext = _pickedName!.toLowerCase().split('.').last;
    final canConvert = _printer == PrinterTarget.yJet &&
        _yJetBlackFix &&
        _colorMode == FileColorMode.cmyk &&
        (ext == 'tif' || ext == 'tiff');
    if (canConvert) {
      setState(() {
        _converting = true;
        _message = 'Converting K black to C95 M95 Y95…';
      });
      try {
        // Streaming conversion: the file is never held whole in
        // memory, so there is no size limit.
        tempConverted =
            File('${Directory.systemTemp.path}/$sendName');
        await convertCmykTiffBlackFile(input: file, output: tempConverted);
        sendFile = tempConverted;
        sendSize = await tempConverted.length();
        blackConverted = true;
        colorModeLabel = 'CMYK';
      } catch (e) {
        if (mounted) {
          setState(() {
            _converting = false;
            _message =
                'Conversion failed, so the original file was NOT sent: $e\nRe-export a CMYK TIFF from Photoshop / Illustrator and send that.';
          });
        }
        return;
      } finally {
        if (mounted) setState(() => _converting = false);
      }
    }

    // Customer / Order / Size / Quantity — total remove (2026-11-13).
    // Model fields stay '' / 1 only so old jobs.json files still load.
    final job = PrintJob(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: sendName,
      customerName: '',
      orderNo: '',
      size: '',
      material: _material,
      quantity: 1,
      note: _noteController.text.trim(),
      designerName: designer,
      printer: _printer,
      status: JobStatus.pending,
      receivedAt: DateTime.now(),
      filePath: sendFile.path,
      fileSizeBytes: sendSize,
      colorMode: colorModeLabel,
      blackConverted: blackConverted,
      originalFileName: blackConverted ? _pickedName! : '',
    );
    setState(() {
      _uploading = true;
      _progress = 0;
      _message = null;
    });
    try {
      await TransferService.uploadFile(
        host: host,
        file: sendFile,
        job: job,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await _sentStore?.add(job);
      await _loadSent();
      if (mounted) {
        setState(() {
          _uploading = false;
          _message = blackConverted
              ? 'Sent — CMYK TIFF delivered (Black: C95 M95 Y95).'
              : 'Sent — file delivered to ${_printer.label} PC.';
          _pickedFile = null;
          _pickedName = null;
          _colorMode = FileColorMode.unknown;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _message = 'Could not send: $e';
        });
      }
    } finally {
      try {
        await tempConverted?.delete();
      } catch (_) {
        // Temp file cleanup is best-effort only.
      }
    }
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
        final body = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _printerCard(context)),
                  const SizedBox(width: 16),
                  Expanded(flex: 6, child: _fileCard(context)),
                ],
              )
            : Column(
                children: [
                  _printerCard(context),
                  const SizedBox(height: 16),
                  _fileCard(context),
                ],
              );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _identityBar(context),
                const SizedBox(height: 16),
                body,
                const SizedBox(height: 24),
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
          width: 26,
          height: 26,
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

  Widget _identityBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name =
        widget.designerName.isEmpty ? 'Name not set' : widget.designerName;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            ProfilePhotoAvatar(designerName: widget.designerName, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
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

  Widget _printerCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('1', 'Which printer to send to?'),
            const SizedBox(height: 14),
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
                            vertical: 20, horizontal: 12),
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
                              size: 32,
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
            const SizedBox(height: 16),
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
                          ? '${_printer.label} PC IP not set — enter it in Profile (gear icon).'
                          : '${_printer.label} PC:  $_currentIp',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (_online != null)
                    Icon(
                      _online! ? Icons.check_circle : Icons.error,
                      color: _online! ? Colors.green : Colors.red,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _checking ? null : _checkOnline,
                icon: const Icon(Icons.wifi_find, size: 18),
                label: Text(
                    _checking ? 'Checking…' : 'Is the printer PC online?'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('2', 'File and job details'),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickFile,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 26, horizontal: 16),
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
                      _pickedName == null
                          ? Icons.cloud_upload_outlined
                          : Icons.insert_drive_file,
                      size: 36,
                      color: SigntechTheme.brandBlue,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _pickedName ?? 'Choose a file',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _pickedName == null
                          ? 'CMYK files only (TIF / EPS) — the file keeps the exact name you send it with'
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
                                  fileSizeBytes: _pickedSize)
                              .sizeLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            if (_pickedName != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _colorMode == FileColorMode.cmyk
                          ? Colors.green.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Colour: ${_colorMode.label}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (_colorMode == FileColorMode.cmyk &&
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
              if (_colorMode == FileColorMode.cmyk) ...[
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
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Human Y-Jet Black Fix: C95 M95 Y95',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'This printer has no K (black) head — K black in CMYK files is rebuilt from 3 colours (C95 M95 Y95). RGB files are not accepted.',
                ),
                value: _yJetBlackFix,
                activeColor: SigntechTheme.brandBlue,
                onChanged: (v) => setState(() => _yJetBlackFix = v),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _material,
              decoration: const InputDecoration(
                labelText: 'Material',
                border: OutlineInputBorder(),
              ),
              items: kMaterials
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _material = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
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
                          : _printer == PrinterTarget.yJet &&
                                  _yJetBlackFix &&
                                  _colorMode == FileColorMode.cmyk
                              ? 'Convert black and send (K → C95/M95/Y95)'
                              : 'Send file to ${_printer.label}',
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
                  leading: ProfilePhotoAvatar(
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
