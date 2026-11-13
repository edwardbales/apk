import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/print_job.dart';
import '../theme.dart';
import '../services/job_store.dart';
import '../services/ok_folder.dart';
import '../services/rip_app.dart';
import '../services/rip_folder.dart';
import '../services/printer_server.dart';
import '../services/sound_alert.dart';
import '../services/transfer_service.dart';
import '../widgets/designer_avatar.dart';
import '../widgets/job_detail_card.dart';
import '../widgets/job_section_tabs.dart';

/// Which main view the printer dashboard shows. The sidebar
/// NAVIGATION buttons switch between them (v1.23): Dashboard is
/// the stats + incoming-files list, Jobs is the full detail view
/// of every job — designer photo, file, sent time, design details.
enum _PrinterNavPage { dashboard, jobs }

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
  // The operator's saved RIP folder (null = default folder).
  String? _customRipPath;
  // The operator's saved RIP program (null = not picked yet).
  String? _ripAppPath;
  Timer? _okTimer;
  List<PrintJob> _jobs = <PrintJob>[];
  List<String> _ips = <String>[];
  String? _serverError;
  String? _message;
  bool _starting = false;
  JobStatus? _statusFilter; // null = sob
  String? _designerFilter; // null = sob designer
  _PrinterNavPage _page = _PrinterNavPage.dashboard;
  // Jobs view section (v1.25): Active vs Complete.
  JobSection _section = JobSection.active;
  // Arrival sound (v1.26): beep once per new file, never for
  // jobs that were already there at startup.
  bool _soundOn = true;
  final Set<String> _knownJobIds = <String>{};
  bool _firstJobsLoad = true;

  /// After every job-list update: any id we have not seen
  /// before is a newly arrived file — beep once (if sound is
  /// on). The first load only seeds the known set, so starting
  /// the app never beeps for yesterday's files.
  void _noteNewJobs() {
    final fresh = newJobIds(knownIds: _knownJobIds, jobs: _jobs);
    _knownJobIds
      ..addAll(fresh)
      ..retainAll(_jobs.map((j) => j.id));
    if (_firstJobsLoad) {
      _firstJobsLoad = false;
      return;
    }
    if (fresh.isNotEmpty && _soundOn) {
      unawaited(playNewFileSound());
    }
  }

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
    final defaultDir = Directory(
        '${docs.path}/Signtech File Sharing/Incoming/${widget.printer.folderName}');
    // jobs.json stays in the DEFAULT folder so the job list
    // survives a RIP-folder change (see rip_folder.dart).
    final store = JobStore(defaultDir);
    final jobs = await store.load();
    final ips = await localIPv4Addresses();
    // RIP folder: the operator's saved choice, else the default.
    String? savedPath;
    try {
      savedPath = await loadSavedRipFolder(widget.printer);
    } catch (_) {
      savedPath = null;
    }
    var customPath =
        (savedPath != null && savedPath.isNotEmpty) ? savedPath : null;
    var dir = resolveRipFolder(defaultDir: defaultDir, savedPath: customPath);
    String? message;
    if (customPath != null) {
      // The saved folder must exist (or be creatable) — a RIP
      // folder on a disconnected drive falls back to default.
      try {
        await dir.create(recursive: true);
      } catch (_) {
        await saveRipFolder(widget.printer, null);
        dir = defaultDir;
        customPath = null;
        message = 'Saved RIP folder not available — using the default folder.';
      }
    }
    // RIP program (v1.26): the operator picks the RIP .exe
    // once; null = not picked yet.
    String? ripApp;
    try {
      ripApp = await loadRipApp(widget.printer.name);
    } catch (_) {
      ripApp = null;
    }
    // Sound toggle (v1.26): the operator can silence the
    // arrival beep. Default ON.
    bool soundOn = true;
    try {
      soundOn = await loadSoundOn(widget.printer.name);
    } catch (_) {
      soundOn = true;
    }
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
      _customRipPath = customPath;
      _ripAppPath = ripApp;
      _soundOn = soundOn;
      if (message != null) _message = message;
    });
    // Seeds the known ids — no beep for files already here.
    _noteNewJobs();
    await _startServer();
    await _checkOkFolder();
    _okTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _checkOkFolder());
  }

  /// Let the operator choose the RIP folder. The server restarts
  /// on the new folder; new files land there, the OK folder moves
  /// with it, and the job list is kept (jobs.json stays default).
  Future<void> _pickRipFolder() async {
    String? picked;
    try {
      picked = await FilePicker.platform.getDirectoryPath();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the folder picker.')),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;
    final ok = await _applyRipFolder(Directory(picked));
    if (!ok || !mounted) return;
    await saveRipFolder(widget.printer, picked);
    setState(() {
      _customRipPath = picked;
      _message = 'RIP folder set: $picked';
    });
  }

  /// Back to the default Incoming folder.
  Future<void> _resetRipFolder() async {
    final docs = await getApplicationDocumentsDirectory();
    final defaultDir = Directory(
        '${docs.path}/Signtech File Sharing/Incoming/${widget.printer.folderName}');
    final ok = await _applyRipFolder(defaultDir);
    if (!ok || !mounted) return;
    await saveRipFolder(widget.printer, null);
    setState(() {
      _customRipPath = null;
      _message = 'RIP folder reset to the default folder.';
    });
  }

  /// Point the printer at [dir]: make sure its OK folder exists,
  /// stop the server, restart it on the new folder. Returns false
  /// when the folder cannot be used (server keeps the old folder).
  Future<bool> _applyRipFolder(Directory dir) async {
    final okDir = Directory('${dir.path}/OK');
    try {
      await okDir.create(recursive: true);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'That folder could not be used.');
      }
      return false;
    }
    await _server?.stop();
    _server = null;
    if (mounted) {
      setState(() {
        _incomingDir = dir;
        _okDir = okDir;
      });
    }
    await _startServer();
    await _checkOkFolder();
    return true;
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
        setState(
            () => _message = 'Auto Done: $name was moved to the OK folder.');
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
            _message =
                'New file received: ${job.fileName} (${job.designerName})';
          });
          _noteNewJobs();
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
    if (mounted) {
      setState(() => _jobs = jobs);
      _noteNewJobs();
    }
  }

  /// Let the operator pick the RIP program (.exe) once (v1.26).
  /// Any RIP works — the app never assumes a brand.
  Future<void> _pickRipApp() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the file picker.')),
        );
      }
      return;
    }
    final path = result?.files.single.path;
    if (path == null || path.isEmpty || !mounted) return;
    await saveRipApp(widget.printer.name, path);
    setState(() {
      _ripAppPath = path;
      _message = 'RIP program set: ${path.split(Platform.pathSeparator).last}';
    });
  }

  /// Forget the RIP program (the button falls back to asking
  /// the operator to pick it again).
  Future<void> _clearRipApp() async {
    await saveRipApp(widget.printer.name, null);
    setState(() {
      _ripAppPath = null;
      _message = 'RIP program cleared.';
    });
  }

  /// Opens a job's file in the saved RIP program (v1.26) — one
  /// click from the job card instead of browsing to the folder.
  Future<void> _openInRip(PrintJob job) async {
    final appPath = _ripAppPath;
    if (appPath == null) {
      setState(() => _message =
          'Select the RIP program first — sidebar → RIP software.');
      return;
    }
    try {
      await openInRip(appPath: appPath, filePath: job.filePath);
      setState(() => _message = 'Opened in RIP: ${job.fileName}');
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    }
  }

  /// Toggles the arrival beep (v1.26) and persists the choice
  /// for this printer PC.
  Future<void> _toggleSound() async {
    final on = !_soundOn;
    setState(() => _soundOn = on);
    try {
      await saveSoundOn(widget.printer.name, on);
    } catch (_) {
      // The toggle still works for this session.
    }
  }

  Future<void> _setStatus(PrintJob job, JobStatus status) async {
    await _store?.updateStatus(job.id, status);
    await _refresh();
  }

  /// Clears the finished jobs from the list (v1.25) — only from
  /// the Complete section, and only after the operator confirms.
  /// The FILES stay on disk in their job folders / the OK folder;
  /// only the list entries are removed, so old done jobs stop
  /// piling up. Active jobs are never touched.
  Future<void> _clearCompleted() async {
    final store = _store;
    if (store == null || _completeCount == 0) return;
    final count = _completeCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear completed jobs?'),
        content: Text(
          'This removes $count completed job${count == 1 ? '' : 's'} '
          'from the list. The files themselves stay in the '
          'Incoming folder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await store.clearCompleted();
    await _refresh();
    if (mounted) {
      setState(() => _message = 'Cleared $removed completed job${removed == 1 ? '' : 's'}.');
    }
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
      setState(
          () => _message = 'File ta khuje pawa jacche na: ${job.filePath}');
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
      // Section first (v1.25): Active = still to print,
      // Complete = finished on this printer.
      final isComplete = job.status == JobStatus.done ||
          job.status == JobStatus.forwarded;
      if (_section == JobSection.active && isComplete) return false;
      if (_section == JobSection.complete && !isComplete) return false;
      if (_statusFilter != null && job.status != _statusFilter) {
        return false;
      }
      if (_designerFilter != null && job.designerName != _designerFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  int get _activeCount => _jobs
      .where((j) =>
          j.status != JobStatus.done && j.status != JobStatus.forwarded)
      .length;

  int get _completeCount => _jobs.length - _activeCount;

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

  @override
  Widget build(BuildContext context) {
    final jobs = _filteredJobs;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The printer dashboard is ALWAYS the sidebar panel system
        // (the v1.11 design) — no top-header card at any width.
        // At portrait widths the sidebar is narrower (240px) so
        // the job list still has room beside it.
        final narrow = constraints.maxWidth <= 640;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sidebar(context, width: narrow ? 240 : 272, narrow: narrow),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: ListView(
                    padding: EdgeInsets.all(narrow ? 12 : 16),
                    children: _page == _PrinterNavPage.jobs
                        ? _jobsChildren(context, jobs, narrow: narrow)
                        : _mainChildren(context, narrow: narrow),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The Dashboard main area (right of the sidebar): an
  /// at-a-glance overview only — stats + OK folder banner.
  /// The files themselves live ONLY under Jobs (v1.24, on the
  /// user's correction: the job list does not stay here).
  List<Widget> _mainChildren(BuildContext context,
      {required bool narrow}) {
    final scheme = Theme.of(context).colorScheme;
    return [
      _statsRow(context, narrow: narrow),
      const SizedBox(height: 12),
      _okFolderBanner(context, narrow: narrow),
      const SizedBox(height: 16),
      if (_message != null) ...[
        Text(_message!, style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
      ],
      Text(
        'Files live under Jobs — open Jobs to see every design, '
        'its designer and all details.',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
    ];
  }

  /// The Jobs view (v1.23): every job opened up with its full
  /// details — designer photo, file, sent time, design details.
  /// The ONLY place the files are listed (v1.24): the dashboard
  /// keeps just the stats + OK banner. Filters + actions per job.
  List<Widget> _jobsChildren(BuildContext context, List<PrintJob> jobs,
      {required bool narrow}) {
    final scheme = Theme.of(context).colorScheme;
    final isComplete = _section == JobSection.complete;
    return [
      Row(
        children: [
          Text(
            'Jobs',
            style: TextStyle(
                fontSize: narrow ? 16 : 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Text('${jobs.length}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15)),
          const Spacer(),
          IconButton(
            onPressed: _openFolder,
            icon: Icon(Icons.folder_open, size: narrow ? 20 : 24),
            tooltip: 'Open RIP folder',
            padding: EdgeInsets.all(narrow ? 4 : 8),
            constraints: BoxConstraints(
                minWidth: narrow ? 32 : 48, minHeight: narrow ? 32 : 48),
          ),
          IconButton(
            onPressed: _refresh,
            icon: Icon(Icons.refresh, size: narrow ? 20 : 24),
            tooltip: 'Refresh',
            padding: EdgeInsets.all(narrow ? 4 : 8),
            constraints: BoxConstraints(
                minWidth: narrow ? 32 : 48, minHeight: narrow ? 32 : 48),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // Active / Complete sections (v1.25): a finished file
      // lands in Complete the moment it turns Done.
      JobSectionTabs(
        section: _section,
        activeCount: _activeCount,
        completeCount: _completeCount,
        onSectionChanged: (section) {
          // A status chip from the other section would filter
          // everything out — start each section at All.
          setState(() {
            _section = section;
            _statusFilter = null;
          });
        },
      ),
      const SizedBox(height: 12),
      _filters(context),
      const SizedBox(height: 12),
      if (isComplete && _completeCount > 0)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _clearCompleted,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Clear completed'),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          ),
        ),
      if (_jobs.isEmpty)
        Text('No files yet.', style: TextStyle(color: scheme.onSurfaceVariant))
      else if ((isComplete ? _completeCount : _activeCount) == 0)
        // The section itself is empty (not the filter — a status
        // chip from the other section cannot be active here).
        Text(
            isComplete
                ? 'No completed jobs yet.'
                : 'No active jobs.',
            style: TextStyle(color: scheme.onSurfaceVariant))
      else if (jobs.isEmpty)
        Text('No files match this filter.',
            style: TextStyle(color: scheme.onSurfaceVariant))
      else
        ...jobs.map((job) => JobDetailCard(
              job: job,
              narrow: narrow,
              otherPrinterLabel: _otherPrinter.label,
              onSetStatus: (j, s) => _setStatus(j, s),
              onForward: (j) => _forward(j),
              onOpenInRip: (j) => _openInRip(j),
            )),
    ];
  }

  /// One sidebar navigation button (v1.23). The selected page
  /// is filled brand blue; Jobs carries a count badge so the
  /// operator sees at a glance how many jobs there are.
  Widget _navButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required _PrinterNavPage page,
    int? badge,
  }) {
    final selected = _page == page;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () {
          if (_page != page) setState(() => _page = page);
        },
        icon: Icon(icon,
            size: 20,
            color: selected ? SigntechTheme.brandBlue : scheme.onSurface),
        label: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? SigntechTheme.brandBlue
                      : scheme.onSurface,
                ),
              ),
            ),
            if (badge != null && badge > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: SigntechTheme.brandBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
          ],
        ),
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? SigntechTheme.brandBlue.withOpacity(0.12)
              : Colors.transparent,
          alignment: Alignment.centerLeft,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  /// Left panel: logo, printer profile, server IP, and the
  /// Light / Dark + Profile buttons. Everything the operator
  /// needs to know about this PC lives here — the main area
  /// is only the incoming files.
  Widget _sidebar(BuildContext context,
      {required double width, required bool narrow}) {
    final scheme = Theme.of(context).colorScheme;
    final running = _server?.isRunning == true;
    final ipReady = _incomingDir != null;
    final address = _ips.isNotEmpty ? '${_ips.first}:$kDefaultPort' : '';
    return Container(
      width: width,
      height: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      // Theme + Profile stay pinned at the bottom (v1.21): the
      // sidebar gained the RIP FOLDER card, so the cards scroll
      // while the two buttons never scroll away.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
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
                  Text('NAVIGATION',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  _navButton(
                    context,
                    label: 'Dashboard',
                    icon: Icons.dashboard,
                    page: _PrinterNavPage.dashboard,
                  ),
                  const SizedBox(height: 8),
                  _navButton(
                    context,
                    label: 'Jobs',
                    icon: Icons.work_outline,
                    page: _PrinterNavPage.jobs,
                    badge: _jobs.length,
                  ),
                  const SizedBox(height: 24),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      border: Border.all(color: Theme.of(context).dividerColor),
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
                                style: TextStyle(
                                    fontSize: narrow ? 14 : 16,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (address.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                tooltip: 'Copy IP',
                                padding: EdgeInsets.all(narrow ? 4 : 8),
                                constraints: BoxConstraints(
                                    minWidth: narrow ? 32 : 48,
                                    minHeight: narrow ? 32 : 48),
                                onPressed: () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: address));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('IP copied.'),
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
                              style: const TextStyle(color: Colors.redAccent)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('RIP FOLDER',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The effective RIP folder (the operator's choice,
                        // else the default Incoming folder). Kept short so
                        // the theme / profile buttons still fit at 650px.
                        Text(
                          _customRipPath ??
                              'Documents/Signtech File Sharing/Incoming/${widget.printer.folderName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: scheme.onSurface),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _pickRipFolder,
                            icon: const Icon(Icons.folder_open, size: 18),
                            label: const Text('Select folder'),
                          ),
                        ),
                        if (_customRipPath != null) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: _resetRipFolder,
                              child: const Text('Back to default folder'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('RIP SOFTWARE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The RIP program the job cards open files
                        // in (v1.26). Pick it once — any RIP works.
                        Text(
                          _ripAppPath == null
                              ? 'Not selected — pick the RIP program once, then job cards open files in it.'
                              : _ripAppPath!
                                  .split(Platform.pathSeparator)
                                  .last,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: scheme.onSurface),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _pickRipApp,
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Select RIP program'),
                          ),
                        ),
                        if (_ripAppPath != null) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: _clearRipApp,
                              child: const Text('Clear RIP program'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(color: Theme.of(context).dividerColor, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onToggleTheme,
                  icon:
                      Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
                  label: Text(widget.isDark ? 'Light theme' : 'Dark theme'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _toggleSound,
                  icon: Icon(
                      _soundOn ? Icons.volume_up : Icons.volume_off,
                      size: 18),
                  label: Text(_soundOn ? 'Sound on' : 'Sound off'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: widget.onOpenProfile,
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Profile / Settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How the OK folder works + a button to open it.
  /// Kept small on purpose (v1.21): one short line of text, a
  /// single row when wide, a short stack when narrow.
  Widget _okFolderBanner(BuildContext context, {required bool narrow}) {
    final scheme = Theme.of(context).colorScheme;
    final button = TextButton.icon(
      onPressed: _openOkFolder,
      icon: const Icon(Icons.folder_open, size: 18),
      label: const Text('Open OK folder'),
    );
    const icon = CircleAvatar(
      backgroundColor: Colors.green,
      radius: 18,
      child: Icon(Icons.folder_special, color: Colors.white, size: 20),
    );
    const title = Text('OK folder — auto Done',
        style: TextStyle(fontWeight: FontWeight.w700));
    // Narrow (beside the 240px sidebar the banner is only ~166px
    // wide): the full title wraps to three lines, so the stacked
    // layout uses the short 'OK folder' — the title already says
    // the file turns Done by itself.
    const narrowTitle =
        Text('OK folder', style: TextStyle(fontWeight: FontWeight.w700));
    final subtitle = Text(
      'Print in RIP, move it to the OK folder.',
      maxLines: narrow ? null : 1,
      overflow: narrow ? TextOverflow.clip : TextOverflow.ellipsis,
      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
    );
    return Card(
      color: Colors.green.withOpacity(0.08),
      // Narrow (portrait, e.g. 430px window): a ListTile squeezes
      // the text into a thin column next to the button — stack it
      // instead so the banner stays short and readable. (This uses
      // the parent's narrow flag, NOT a LayoutBuilder: beside the
      // sidebar the banner is ~500px wide even on an 800px window,
      // so its own width would pick the wrong branch.)
      child: narrow
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    icon,
                    SizedBox(width: 10),
                    Expanded(child: narrowTitle),
                  ]),
                  const SizedBox(height: 6),
                  subtitle,
                  const SizedBox(height: 2),
                  Align(alignment: Alignment.centerRight, child: button),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [title, subtitle],
                    ),
                  ),
                  const SizedBox(width: 8),
                  button,
                ],
              ),
            ),
    );
  }

  Widget _statsRow(BuildContext context, {required bool narrow}) {
    int count(JobStatus s) => _jobs.where((j) => j.status == s).length;
    final scheme = Theme.of(context).colorScheme;
    final stats = <(String, int, Color)>[
      ('Total', _jobs.length, scheme.onSurface),
      ('Pending', count(JobStatus.pending), Colors.orange),
      ('Printing', count(JobStatus.printing), Colors.blue),
      ('Done', count(JobStatus.done), Colors.green),
    ];
    Widget cell(int i) {
      return Expanded(
        child: Column(
          children: [
            Text('${stats[i].$2}',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: stats[i].$3)),
            const SizedBox(height: 2),
            Text(stats[i].$1,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        // Narrow: 4 stats in one row would squeeze every label
        // — 2x2 grid instead.
        child: narrow
            ? Column(
                children: [
                  Row(children: [cell(0), cell(1)]),
                  const SizedBox(height: 10),
                  Row(children: [cell(2), cell(3)]),
                ],
              )
            : Row(
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0)
                      Container(
                          width: 1,
                          height: 34,
                          color: Theme.of(context).dividerColor),
                    cell(i),
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
            // Status chips follow the section (v1.25): Active
            // offers Pending / Printing, Complete offers
            // Done / Forwarded — a chip for a status that
            // cannot appear in this section would be dead.
            for (final s in _section == JobSection.complete
                ? [JobStatus.done, JobStatus.forwarded]
                : [JobStatus.pending, JobStatus.printing])
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
                    onSelected: (_) => setState(() =>
                        _designerFilter = _designerFilter == d ? null : d),
                    avatar: DesignerAvatar(name: d, size: 24),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
