import 'dart:convert';
import 'dart:io';

import '../models/print_job.dart';

/// LAN server that runs on a Printer PC.
///
///   GET  /ping    -> 200 "signtech-ok"
///   POST /upload  -> saves the raw body to the Incoming folder and
///                     records a PrintJob (Pending).
///   GET  /status  -> 200 {"jobs":[{"id":"...","status":"done"}]}
///                     — the Designer PC polls this so it can tell
///                     the designer when a file is Printing Ready.
///
/// The body is streamed straight to disk (request.pipe) so a
/// 100+ MB banner file never sits fully in memory. The server never
/// talks to the internet and never opens RIP itself — the operator
/// opens the saved file in RIP, as the shop already does.
class PrinterServer {
  PrinterServer({
    required this.saveDirectory,
    required this.printer,
    required this.onJobReceived,
    this.port = kDefaultPort,
    this.listJobs,
  });

  final Directory saveDirectory;
  final PrinterTarget printer;
  final void Function(PrintJob job) onJobReceived;
  final int port;

  /// Current jobs on this printer PC (the screen's live list).
  /// Used only by GET /status so the Designer PC can poll.
  final List<PrintJob> Function()? listJobs;

  HttpServer? _server;

  bool get isRunning => _server != null;

  int get boundPort => _server?.port ?? port;

  Future<void> start() async {
    if (_server != null) return;
    await saveDirectory.create(recursive: true);
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/ping') {
        request.response
          ..statusCode = 200
          ..write('signtech-ok');
        await request.response.close();
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/upload') {
        await _handleUpload(request);
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/status') {
        final jobs = listJobs?.call() ?? <PrintJob>[];
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'jobs': jobs
                .map((j) => {'id': j.id, 'status': j.status.name})
                .toList(),
          }));
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = 404
        ..write('not found');
      await request.response.close();
    } catch (e) {
      try {
        request.response
          ..statusCode = 500
          ..write('error: $e');
        await request.response.close();
      } catch (_) {
        // Client already gone — nothing left to do.
      }
    }
  }

  String _header(HttpRequest request, String name) {
    final value = request.headers.value(name);
    if (value == null || value.isEmpty) return '';
    return Uri.decodeComponent(value);
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final fileName = _header(request, 'x-signtech-file-name');
    if (fileName.isEmpty) {
      request.response
        ..statusCode = 400
        ..write('missing file name');
      await request.response.close();
      return;
    }
    // Keep only the file name — a crafted header must never escape
    // the Incoming folder (e.g. "../../Windows/...").
    // The file name is NEVER changed: no suffix, no " (2)".
    // Same-named files from different jobs do not overwrite each
    // other because each job gets its own folder below.
    final safeName = fileName.split(RegExp(r'[\\/]')).last;
    final jobId = _header(request, 'x-signtech-id').isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : _header(request, 'x-signtech-id');
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    // No Order No any more — folder is date + job id only.
    final folderName = '${date}_$jobId';
    final jobDir = Directory('${saveDirectory.path}/$folderName');
    await jobDir.create(recursive: true);
    final targetPath = '${jobDir.path}/$safeName';
    final target = File(targetPath);
    final sink = target.openWrite();
    try {
      await sink.addStream(request);
    } finally {
      await sink.close();
    }
    final size = await target.length();
    final job = PrintJob(
      id: _header(request, 'x-signtech-id').isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : _header(request, 'x-signtech-id'),
      fileName: safeName,
      customerName: _header(request, 'x-signtech-customer'),
      orderNo: _header(request, 'x-signtech-order'),
      size: _header(request, 'x-signtech-size'),
      material: _header(request, 'x-signtech-material'),
      quantity: int.tryParse(_header(request, 'x-signtech-quantity')) ?? 1,
      note: _header(request, 'x-signtech-note'),
      designerName: _header(request, 'x-signtech-designer'),
      printer: printer,
      status: JobStatus.pending,
      receivedAt: DateTime.now(),
      filePath: targetPath,
      fileSizeBytes: size,
      colorMode: _header(request, 'x-signtech-color-mode').isEmpty
          ? 'Unknown'
          : _header(request, 'x-signtech-color-mode'),
      blackConverted: _header(request, 'x-signtech-black') == 'cmy',
      originalFileName: _header(request, 'x-signtech-original-file'),
    );
    onJobReceived(job);
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'ok': true, 'fileName': safeName}));
    await request.response.close();
  }
}
