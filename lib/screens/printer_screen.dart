import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/print_job.dart';
import '../theme.dart';
import '../services/job_store.dart';
import '../services/ok_folder.dart';
import '../services/printer_server.dart';
import '../services/transfer_service.dart';
import '../widgets/designer_avatar.dart';

/// Printer PC screen (Human Y-Jet or Challenger).
///
/// Runs the LAN server, saves incoming files to
/// Documents/Signtech File Sharing/Incoming/<Printer>/ and shows
/// the job list. The operator opens the file in RIP — this app
/// never prints directly.
class PrinterScreen extends StatefulWidget {
  const PrinterScreen({
    super.key,
    required this.printer,
    required this.otherPrinterIp,
    required this.onOtherPrinterIpChanged,
    required this.isDark,
    required this.onToggleTheme,
    required this.onOpenProfile,
  });

  final PrinterTarget printer;
  final String otherPrinterIp;
  final ValueChanged<String> onOtherPrinterIpChanged;

  /// Current theme (HomePage owns it) — the sidebar has the
  /// Light / Dark switch, so the top bar has no theme button
  /// on the printer dashboard.
  final bool isDark;
  final VoidCallback onToggleTheme;

  /// Opens Profile / Settings (gear) — the sidebar button.
  final VoidCallback onOpenProfile;

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  PrinterServer? _server;
  JobStore? _store;
  Directory? _incomingDir;
  Directory? _okDir;
  Timer? _okTimer;
  List<PrintJob> _jobs = <PrintJob>[];
  List<String> _ips = <String>[];
  String? _serverError;
  String? _message;
  bool _starting = false;
  JobStatus? _statusFilter; // null = sob
  String? _designerFilter; // null = sob designer

  PrinterTarget get _otherPrinter => widget.printer == PrinterTarget.yJet
      ? PrinterTarget.challenger
      : PrinterTarget.yJet;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _okTimer?.cancel();
    _server?.stop();
    super.dispose();
  }

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
        '${docs.path}/Signtech File Sharing/Incoming/${widget.printer.folderName}');
    final store = JobStore(dir);
    final jobs = await store.load();
    final ips = await localIPv4Addresses();
    // The OK folder lives inside the RIP folder — the app creates
    // it, the operator only moves printed files into it.
    final okDir = Directory('${dir.path}/OK');
    await okDir.create(recursive: true);
    if (!mounted) return;
    setState(() {
      _incomingDir = dir;
      _okDir = okDir;
      _store = store;
      _jobs = jobs;
      _ips = ips;
    });
    await _startServer();
    await _checkOkFolder();
    _okTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _checkOkFolder());
  }

  /// Scans the OK folder: any file whose name matches a job that
  /// is not Done yet marks that job Done automatically.
  Future<void> _checkOkFolder() async {
    final okDir = _okDir;
    final store = _store;
    if (okDir == null || store == null) return;
    if (!await okDir.exists()) return;
    final entries = await okDir.list().toList();
    var changed = false;
    for (final entry in entries) {
      if (entry is! File) continue;
      final name = entry.path.split(Platform.pathSeparator).last;
      final job = findJobForOkFile(jobs: _jobs, fileName: name);
      if (job == null) continue;
      await store.updateStatus(job.id, JobStatus.done);
      changed = true;
      if (mounted) {
        setState(() => _message =
            'Auto Done: $name was moved to the OK folder.');
      }
    }
    if (changed) await _refresh();
  }

  Future<void> _openOkFolder() async {
    final dir = _okDir;
    if (dir == null) return;
    if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    }
  }

  Future<void> _startServer() async {
    if (_incomingDir == null || _server?.isRunning == true) return;
    setState(() {
      _starting = true;
      _serverError = null;
    });
    final server = PrinterServer(
      saveDirectory: _incomingDir!,
      printer: widget.printer,
      listJobs: () => _jobs,
      onJobReceived: (job) async {
        await _store?.add(job);
        if (mounted) {
          final jobs = await _store?.load() ?? <PrintJob>[];
          setState(() {
            _jobs = jobs;
            _message = 'New file received: ${job.fileName} (${job.designerName})';
          });
        }
      },
    );
    try {
      await server.start();
      if (mounted) setState(() => _server = server);
    } catch (e) {
      if (mounted) {
        setState(() => _serverError =
            'Server could not start (check if port $kDefaultPort is already in use): $e');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _refresh() async {
    final jobs = await _store?.load() ?? <PrintJob>[];
    if (mounted) setState(() => _jobs = jobs);
  }

  Future<void> _setStatus(PrintJob job, JobStatus status) async {
    await _store?.updateStatus(job.id, status);
    await _refresh();
  }

  Future<void> _openFolder() async {
    final dir = _incomingDir;
    if (dir == null) return;
    if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    }
  }

  Future<void> _forward(PrintJob job) async {
    final otherIpController =
        TextEditingController(text: widget.otherPrinterIp);
    final otherIp = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send to ${_otherPrinter.label}'),
        content: TextField(
          controller: otherIpController,
          decoration: InputDecoration(
            labelText: '${_otherPrinter.label} PC-r IP',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, otherIpController.text.trim()),
            child: const Text('Pathao'),
          ),
        ],
      ),
    );
    if (otherIp == null || otherIp.isEmpty) return;
    widget.onOtherPrinterIpChanged(otherIp);
    final file = File(job.filePath);
    if (!await file.exists()) {
      setState(() => _message = 'File ta khuje pawa jacche na: ${job.filePath}');
      return;
    }
    setState(() => _message = 'Forwarding…');
    try {
      await TransferService.forwardFile(host: otherIp, file: file, job: job);
      await _setStatus(job, JobStatus.forwarded);
      if (mounted) {
        setState(() => _message =
            'Forwarded — file delivered to ${_otherPrinter.label} PC.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not forward: $e');
    }
  }

  // ------------------------------------------------------------------
  //  Professional layout
  //
  //  Top: server status card + stats row (Total / Pending /
  //  Printing / Done). Then filters: status + DESIGNER — so the
  //  operator can see at a glance who sent which file, and filter
  //  to one designer. Each job card starts with the designer's
  //  avatar + name in bold, with their fixed colour.
  // ------------------------------------------------------------------
  List<PrintJob> get _filteredJobs {
    return _jobs.where((job) {
      if (_statusFilter != null && job.status != _statusFilter) {
        return false;
      }
      if (_designerFilter != null &&
          job.designerName != _designerFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  List<String> get _designers {
    final names = <String>{};
    for (final job in _jobs) {
      if (job.designerName.trim().isNotEmpty) {
        names.add(job.designerName);
      }
    }
    final list = names.toList()..sort();
    return list;
  }

  String _timeLabel(DateTime t) {
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm, ${local.day}/${local.month}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final jobs = _filteredJobs;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sidebar(context),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _statsRow(context),
                  const SizedBox(height: 12),
                  _okFolderBanner(context),
                  const SizedBox(height: 16),
                  if (_message != null) ...[
                    Text(_message!,
                        style:
                            TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      const Text(
                        'Incoming files',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      Text('${jobs.length}',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 15)),
                      const Spacer(),
                      IconButton(
                        onPressed: _openFolder,
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Open RIP folder',
                      ),
                      IconButton(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _filters(context),
                  const SizedBox(height: 12),
                  if (_jobs.isEmpty)
                    Text('No files yet.',
                        style: TextStyle(color: scheme.onSurfaceVariant))
                  else if (jobs.isEmpty)
                    Text('No files match this filter.',
                        style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    ...jobs.map((job) => _jobCard(context, job)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Left panel: logo, printer profile, server IP, and the
  /// Light / Dark + Profile buttons. Everything the operator
  /// needs to know about this PC lives here — the main area
  /// is only the incoming files.
  Widget _sidebar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = _server?.isRunning == true;
    final ipReady = _incomingDir != null;
    final address =
        _ips.isNotEmpty ? '${_ips.first}:$kDefaultPort' : '';
    return Container(
      width: 272,
      height: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Signtech File Sharing',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Printer dashboard',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: Theme.of(context).dividerColor, height: 1),
            const SizedBox(height: 20),
            Text('PRINTER PROFILE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SigntechTheme.brandBlue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: SigntechTheme.brandBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.print,
                        size: 26, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.printer.label,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('Printer PC',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (running ? Colors.green : Colors.red)
                    .withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: running ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    running
                        ? 'Server ON'
                        : _starting
                            ? 'Starting server…'
                            : 'Server OFF',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: running ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            if (!running && !_starting && ipReady) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startServer,
                  child: const Text('Start server'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text('SERVER ADDRESS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          ipReady
                              ? (address.isNotEmpty
                                  ? address
                                  : 'IP not found')
                              : 'Finding this PC IP…',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (address.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Copy IP',
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: address));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('IP copied.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Designers enter this IP on their PC to send files here.',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  if (_serverError != null) ...[
                    const SizedBox(height: 8),
                    Text(_serverError!,
                        style:
                            const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Divider(color: Theme.of(context).dividerColor, height: 1),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onToggleTheme,
                icon: Icon(
                    widget.isDark ? Icons.light_mode : Icons.dark_mode),
                label: Text(widget.isDark
                    ? 'Light theme'
                    : 'Dark theme'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.onOpenProfile,
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Profile / Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How the OK folder works + a button to open it.
  Widget _okFolderBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: Colors.green.withOpacity(0.08),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.folder_special, color: Colors.white),
        ),
        title: const Text('OK folder — auto Done',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          'Print a file in RIP, then move it into the OK folder inside the RIP folder — it will be marked Done automatically.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        trailing: TextButton.icon(
          onPressed: _openOkFolder,
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('Open OK folder'),
        ),
      ),
    );
  }

  Widget _statsRow(BuildContext context) {
    int count(JobStatus s) => _jobs.where((j) => j.status == s).length;
    final scheme = Theme.of(context).colorScheme;
    final stats = <(String, int, Color)>[
      ('Total', _jobs.length, scheme.onSurface),
      ('Pending', count(JobStatus.pending), Colors.orange),
      ('Printing', count(JobStatus.printing), Colors.blue),
      ('Done', count(JobStatus.done), Colors.green),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                Container(
                    width: 1,
                    height: 34,
                    color: Theme.of(context).dividerColor),
              Expanded(
                child: Column(
                  children: [
                    Text('${stats[i].$2}',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: stats[i].$3)),
                    const SizedBox(height: 2),
                    Text(stats[i].$1,
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          selectedColor: SigntechTheme.brandBlue,
          labelStyle: TextStyle(
              color: selected ? Colors.white : scheme.onSurface,
              fontWeight: FontWeight.w700),
          onSelected: (_) => onTap(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: [
            chip('All', _statusFilter == null,
                () => setState(() => _statusFilter = null)),
            for (final s in [
              JobStatus.pending,
              JobStatus.printing,
              JobStatus.done,
            ])
              chip(s.label, _statusFilter == s,
                  () => setState(() => _statusFilter = s)),
          ],
        ),
        if (_designers.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: Text('Designer:',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
              ),
              chip('All designers', _designerFilter == null,
                  () => setState(() => _designerFilter = null)),
              for (final d in _designers)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: FilterChip(
                    label: Text(d),
                    selected: _designerFilter == d,
                    selectedColor: designerColor(d).withOpacity(0.25),
                    checkmarkColor: designerColor(d),
                    onSelected: (_) => setState(() => _designerFilter =
                        _designerFilter == d ? null : d),
                    avatar: DesignerAvatar(name: d, size: 24),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _jobCard(BuildContext context, PrintJob job) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = job.status == JobStatus.done
        ? Colors.green
        : job.status == JobStatus.printing
            ? Colors.blue
            : Colors.orange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DesignerAvatar(name: job.designerName, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.designerName.isEmpty
                            ? 'Unknown designer'
                            : job.designerName,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sent a file  •  ${_timeLabel(job.receivedAt)}',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(job.status.label,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: SigntechTheme.brandBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.insert_drive_file,
                      color: SigntechTheme.brandBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.fileName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                          '${job.material}  •  ${job.sizeLabel}  •  ${job.colorMode}'
                          '${job.blackConverted ? '  •  Black C95/M95/Y95' : ''}',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            if (job.originalFileName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Original: ${job.originalFileName}',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12)),
              ),
            if (job.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Note: ${job.note}',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: job.status == JobStatus.printing
                      ? null
                      : () => _setStatus(job, JobStatus.printing),
                  child: const Text('Printing'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: job.status == JobStatus.done
                      ? null
                      : () => _setStatus(job, JobStatus.done),
                  child: const Text('Done'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _forward(job),
                  icon: const Icon(Icons.send, size: 16),
                  label: Text('Send to ${_otherPrinter.label}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
