import 'dart:io';

import 'package:flutter/material.dart';

import '../services/profile_photo.dart';

/// Who sent the file — at a glance.
///
/// Every designer gets a fixed colour from their name, so the
/// operator can tell Designer 1 from Designer 2 without reading
/// any small print: same name = same colour, everywhere.
const List<Color> _kDesignerPalette = <Color>[
  Color(0xFF4F5BD5), // blue
  Color(0xFF0E9F6E), // green
  Color(0xFF7C3AED), // purple
  Color(0xFFEA580C), // orange
  Color(0xFF0891B2), // teal
];

Color designerColor(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return Colors.grey;
  var hash = 0;
  for (final unit in trimmed.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _kDesignerPalette[hash % _kDesignerPalette.length];
}

/// "Designer 1" -> "D1", "Monjurul Islam" -> "MI", "Rafi" -> "RA".
String designerInitials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
  }
  String firstChar(String p) => p.isEmpty ? '' : p[0];
  // "Designer 1" should read D1, not DE.
  final second = parts[1];
  final secondInitial =
      RegExp(r'^[0-9]').hasMatch(second) ? second : firstChar(second);
  return (firstChar(parts.first) + secondInitial).toUpperCase();
}

class DesignerAvatar extends StatelessWidget {
  const DesignerAvatar({super.key, required this.name, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = designerColor(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        designerInitials(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The designer's photo when one is set in Profile, otherwise
/// the initials avatar. Used on the Designer PC only (identity
/// bar + sent list) — the printer PCs show initials.
class ProfilePhotoAvatar extends StatefulWidget {
  const ProfilePhotoAvatar(
      {super.key, required this.designerName, this.size = 44});

  final String designerName;
  final double size;

  @override
  State<ProfilePhotoAvatar> createState() => _ProfilePhotoAvatarState();
}

class _ProfilePhotoAvatarState extends State<ProfilePhotoAvatar> {
  File? _photo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photo = await loadDesignerPhotoFile();
    if (mounted) setState(() => _photo = photo);
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    if (photo != null) {
      return ClipOval(
        child: Image.file(
          photo,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
        ),
      );
    }
    return DesignerAvatar(name: widget.designerName, size: widget.size);
  }
}

/// Small coloured chip with the designer's name — used next to
/// the avatar in job cards and in the filter row.
class DesignerChip extends StatelessWidget {
  const DesignerChip({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final color = designerColor(name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(name,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 13)),
        ],
      ),
    );
  }
}
