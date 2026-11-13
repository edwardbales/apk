import 'dart:convert';
import 'dart:io';

import '../models/print_job.dart';

/// LAN client: Designer PC -> Printer PC.
///
/// Protocol (kept deliberately simple — no multipart parser, no
/// extra server dependency, works with plain dart:io on both ends):
///   GET  /ping    -> 200 "signtech-ok"  (is this printer PC online?)
///   POST /upload  -> raw file bytes as the body, metadata in headers
///                     (x-signtech-* — URI-encoded so Bangla / spaces
///                     survive), returns 200 {"ok":true}
///
/// Header names are lower-cased by HttpClient, so the server reads
/// them lower-case too.
class TransferService {
  static const Duration timeout = Duration(seconds: 10);

  static String pingUrl(String host, int port) => 'http://$host:$port/ping';

  static String uploadUrl(String host, int port) =>
      'http://$host:$port/upload';

  static String statusUrl(String host, int port) =>
      'http://$host:$port/status';

  /// Asks a Printer PC for the current status of its jobs.
  /// Returns job id -> status. Any failure (offline, old version
  /// without /status) returns an empty map — the caller just tries
  /// again on the next poll.
  static Future<Map<String, JobStatus>> fetchStatuses({
    required String host,
    int port = kDefaultPort,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse(statusUrl(host, port)))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return <String, JobStatus>{};
      final body = await response.transform(const SystemEncoding().decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final jobs = decoded['jobs'] as List<dynamic>? ?? <dynamic>[];
      final result = <String, JobStatus>{};
      for (final entry in jobs) {
        final map = entry as Map<String, dynamic>;
        final id = map['id'] as String? ?? '';
        final status = JobStatus.fromName(map['status'] as String? ?? '');
        if (id.isNotEmpty) result[id] = status;
      }
      return result;
    } catch (_) {
      return <String, JobStatus>{};
    } finally {
      client.close();
    }
  }

  static Future<bool> ping({required String host, int port = kDefaultPort}) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse(pingUrl(host, port)))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(const SystemEncoding().decoder).join();
      return response.statusCode == 200 && body.trim() == 'signtech-ok';
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Sends [file] to the printer PC. [onProgress] gets 0.0–1.0.
  /// Throws on network / HTTP errors — the caller shows the message.
  static Future<void> uploadFile({
    required String host,
    int port = kDefaultPort,
    required File file,
    required PrintJob job,
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(Uri.parse(uploadUrl(host, port)))
          .timeout(timeout);
      request.headers.set('x-signtech-file-name',
          Uri.encodeComponent(job.fileName));
      request.headers.set('x-signtech-customer',
          Uri.encodeComponent(job.customerName));
      request.headers.set(
          'x-signtech-order', Uri.encodeComponent(job.orderNo));
      request.headers
          .set('x-signtech-size', Uri.encodeComponent(job.size));
      request.headers.set(
          'x-signtech-material', Uri.encodeComponent(job.material));
      request.headers.set('x-signtech-quantity', '${job.quantity}');
      request.headers
          .set('x-signtech-note', Uri.encodeComponent(job.note));
      request.headers.set('x-signtech-designer',
          Uri.encodeComponent(job.designerName));
      request.headers.set('x-signtech-printer', job.printer.name);
      request.headers.set('x-signtech-id', job.id);
      request.headers.set('x-signtech-color-mode',
          Uri.encodeComponent(job.colorMode));
      request.headers.set(
          'x-signtech-black', job.blackConverted ? 'cmy' : 'off');
      request.headers.set('x-signtech-original-file',
          Uri.encodeComponent(job.originalFileName));
      request.contentLength = await file.length();

      // Stream in 64 KB chunks so a big banner file reports progress
      // and does not need a second full copy in memory.
      final total = request.contentLength;
      var sent = 0;
      final stream = file.openRead();
      await for (final chunk in stream) {
        request.add(chunk);
        sent += chunk.length;
        if (total > 0) onProgress?.call(sent / total);
      }
      final response = await request.close().timeout(const Duration(minutes: 10));
      final body = await response.transform(const SystemEncoding().decoder).join();
      if (response.statusCode != 200) {
        throw HttpException(
            'Printer PC replied ${response.statusCode}: $body');
      }
      onProgress?.call(1.0);
    } finally {
      client.close();
    }
  }

  /// Forwarding is the same upload, to the other printer's IP.
  static Future<void> forwardFile({
    required String host,
    int port = kDefaultPort,
    required File file,
    required PrintJob job,
    void Function(double progress)? onProgress,
  }) {
    return uploadFile(
      host: host,
      port: port,
      file: file,
      job: job,
      onProgress: onProgress,
    );
  }
}

/// All IPv4 addresses of this PC (WiFi + Ethernet), for the Printer
/// screen to show — the Designer types one of these into their PC.
Future<List<String>> localIPv4Addresses() async {
  final result = <String>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        result.add(address.address);
      }
    }
  } catch (_) {
    // No network: the Printer screen shows a hint instead.
  }
  return result;
}
