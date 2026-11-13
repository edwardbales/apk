/// A print file sent from a Designer PC to a Printer PC.
///
/// The file itself travels over the LAN as raw bytes (POST /upload).
/// This model is only the metadata that travels in the HTTP headers
/// and is stored in jobs.json on the printer PC.
enum PrinterTarget {
  yJet,
  challenger;

  String get label {
    switch (this) {
      case PrinterTarget.yJet:
        return 'Human Y-Jet';
      case PrinterTarget.challenger:
        return 'Challenger';
    }
  }

  /// Folder name under the printer PC's Incoming folder.
  String get folderName {
    switch (this) {
      case PrinterTarget.yJet:
        return 'Human-Y-Jet';
      case PrinterTarget.challenger:
        return 'Challenger';
    }
  }

  static PrinterTarget fromName(String name) {
    return PrinterTarget.values.firstWhere(
      (e) => e.name == name,
      orElse: () => PrinterTarget.yJet,
    );
  }
}

enum JobStatus {
  pending,
  printing,
  done,
  forwarded;

  String get label {
    switch (this) {
      case JobStatus.pending:
        return 'Pending';
      case JobStatus.printing:
        return 'Printing';
      case JobStatus.done:
        return 'Done';
      case JobStatus.forwarded:
        return 'Forwarded';
    }
  }

  static JobStatus fromName(String name) {
    return JobStatus.values.firstWhere(
      (e) => e.name == name,
      orElse: () => JobStatus.pending,
    );
  }
}

class PrintJob {
  PrintJob({
    required this.id,
    required this.fileName,
    required this.customerName,
    required this.orderNo,
    required this.size,
    required this.material,
    required this.quantity,
    required this.note,
    required this.designerName,
    required this.printer,
    required this.status,
    required this.receivedAt,
    required this.filePath,
    required this.fileSizeBytes,
    this.colorMode = 'Unknown',
    this.blackConverted = false,
    this.originalFileName = '',
  });

  factory PrintJob.fromJson(Map<String, dynamic> json) {
    return PrintJob(
      id: json['id'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      orderNo: json['orderNo'] as String? ?? '',
      size: json['size'] as String? ?? '',
      material: json['material'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      note: json['note'] as String? ?? '',
      designerName: json['designerName'] as String? ?? '',
      printer: PrinterTarget.fromName(json['printer'] as String? ?? 'yJet'),
      status: JobStatus.fromName(json['status'] as String? ?? 'pending'),
      receivedAt: DateTime.tryParse(json['receivedAt'] as String? ?? '') ??
          DateTime.now(),
      filePath: json['filePath'] as String? ?? '',
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      colorMode: json['colorMode'] as String? ?? 'Unknown',
      blackConverted: json['blackConverted'] as bool? ?? false,
      originalFileName: json['originalFileName'] as String? ?? '',
    );
  }

  final String id;
  final String fileName;
  final String customerName;
  final String orderNo;
  final String size;
  final String material;
  final int quantity;
  final String note;
  final String designerName;
  final PrinterTarget printer;
  final JobStatus status;
  final DateTime receivedAt;
  final String filePath;
  final int fileSizeBytes;

  /// 'RGB' / 'CMYK' / 'Grayscale' / 'Unknown' — detected on upload.
  final String colorMode;

  /// True when the Y-Jet black fix ran: black is C95 M95 Y95 K0 in
  /// the uploaded CMYK TIFF (Human Y-Jet has no K head).
  final bool blackConverted;

  /// The designer's original file name, when the uploaded file is a
  /// converted copy (e.g. banner_YJet-CMYK.tif from banner.jpg).
  final String originalFileName;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'customerName': customerName,
      'orderNo': orderNo,
      'size': size,
      'material': material,
      'quantity': quantity,
      'note': note,
      'designerName': designerName,
      'printer': printer.name,
      'status': status.name,
      'receivedAt': receivedAt.toIso8601String(),
      'filePath': filePath,
      'fileSizeBytes': fileSizeBytes,
      'colorMode': colorMode,
      'blackConverted': blackConverted,
      'originalFileName': originalFileName,
    };
  }

  PrintJob copyWith({JobStatus? status, String? filePath}) {
    return PrintJob(
      id: id,
      fileName: fileName,
      customerName: customerName,
      orderNo: orderNo,
      size: size,
      material: material,
      quantity: quantity,
      note: note,
      designerName: designerName,
      printer: printer,
      status: status ?? this.status,
      receivedAt: receivedAt,
      filePath: filePath ?? this.filePath,
      fileSizeBytes: fileSizeBytes,
      colorMode: colorMode,
      blackConverted: blackConverted,
      originalFileName: originalFileName,
    );
  }

  /// "12.5 MB" / "850 KB" — shown in both Designer and Printer lists.
  String get sizeLabel {
    if (fileSizeBytes >= 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (fileSizeBytes >= 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$fileSizeBytes B';
  }
}

/// Materials used in the shop. Kept as a plain list so a new material
/// is one line — no code change in the screens.
const List<String> kMaterials = <String>[
  'PVC Banner',
  'Flex',
  'Sticker',
  'Backlit',
  'Panaflex',
  'Vinyl',
  'Other',
];

/// Default LAN port. One port for every PC — the Designer only has to
/// type the printer PC's IP, never a different port per printer.
const int kDefaultPort = 8080;

/// ONLY these file formats are accepted — nothing else.
/// (Shop rule, 2026-11-13.)
const List<String> kAllowedExtensions = <String>[
  'tif',
  'tiff',
  'jpg',
  'jpeg',
  'eps',
];

const String kAllowedFormatsLabel = 'TIF / JPG / EPS';

bool isAllowedFileName(String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  return kAllowedExtensions.contains(ext);
}
