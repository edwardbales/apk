import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/print_job.dart';
import '../services/profile_photo.dart';
import '../widgets/designer_avatar.dart';
import '../theme.dart';

/// Profile / Settings screen.
///
/// ONLY these live here:
///   - Designer nam (Designer PC-te)
///   - Printer PC-r IP (Y-Jet + Challenger — Designer PC-te;
///     arek printer-er IP — Printer PC-te)
///
/// Customer nam, Order No, Size, Quantity — egula profile-e
/// THAKE NA. Egula prottek job-er jinish, tai prottek file
/// pathanor somoy upload form-e likhte hoy.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.roleLabel,
    required this.isDesigner,
    required this.designerName,
    required this.yJetIp,
    required this.challengerIp,
    required this.otherPrinterLabel,
    required this.otherPrinterIp,
    required this.onDesignerNameChanged,
    required this.onPrinterIpChanged,
    required this.onOtherPrinterIpChanged,
    required this.onChangeRole,
  });

  final String roleLabel;
  final bool isDesigner;
  final String designerName;
  final String yJetIp;
  final String challengerIp;
  final String otherPrinterLabel;
  final String otherPrinterIp;
  final ValueChanged<String> onDesignerNameChanged;
  final void Function(PrinterTarget printer, String ip) onPrinterIpChanged;
  final ValueChanged<String> onOtherPrinterIpChanged;
  final VoidCallback onChangeRole;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _nameController =
      TextEditingController(text: widget.designerName);
  late final _yJetController = TextEditingController(text: widget.yJetIp);
  late final _challengerController =
      TextEditingController(text: widget.challengerIp);
  late final _otherController =
      TextEditingController(text: widget.otherPrinterIp);
  String? _message;
  File? _photo;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final photo = await loadDesignerPhotoFile();
    if (mounted) setState(() => _photo = photo);
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final saved = await saveDesignerPhoto(File(path));
    if (mounted) {
      setState(() {
        _photo = saved;
        _message = 'Profile photo saved.';
      });
    }
  }

  Future<void> _removePhoto() async {
    await removeDesignerPhoto();
    if (mounted) {
      setState(() {
        _photo = null;
        _message = 'Profile photo removed.';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yJetController.dispose();
    _challengerController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.isDesigner) {
      widget.onDesignerNameChanged(_nameController.text.trim());
      widget.onPrinterIpChanged(
          PrinterTarget.yJet, _yJetController.text.trim());
      widget.onPrinterIpChanged(
          PrinterTarget.challenger, _challengerController.text.trim());
    } else {
      widget.onOtherPrinterIpChanged(_otherController.text.trim());
    }
    setState(() => _message = 'Profile saved.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile / Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: SigntechTheme.brandBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.person,
                        size: 30, color: SigntechTheme.brandBlue),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.roleLabel,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        Text('Signtech File Sharing',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (widget.isDesigner) ...[
                const Text('Profile photo',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_photo != null)
                      ClipOval(
                        child: Image.file(
                          _photo!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      DesignerAvatar(
                          name: widget.designerName, size: 72),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Shown on your Designer screen, next to your name.',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _pickPhoto,
                                icon: const Icon(Icons.photo_camera,
                                    size: 18),
                                label: const Text('Choose photo'),
                              ),
                              if (_photo != null)
                                TextButton(
                                  onPressed: _removePhoto,
                                  child: const Text('Remove'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Your details',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Designer name  (e.g. Designer 1)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const Text('Printer PC IP',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Enter once and it is remembered — no need to type it at upload time.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              if (widget.isDesigner) ...[
                TextField(
                  controller: _yJetController,
                  decoration: const InputDecoration(
                    labelText: 'Human Y-Jet PC IP  (e.g. 192.168.1.101)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _challengerController,
                  decoration: const InputDecoration(
                    labelText: 'Challenger PC IP  (e.g. 192.168.1.102)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else
                TextField(
                  controller: _otherController,
                  decoration: InputDecoration(
                    labelText:
                        '${widget.otherPrinterLabel} PC IP  (for forwarding)',
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Text(
                  'Customer name, Order No, Size, Quantity — these were removed from the app completely.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _save,
                  child: const Text('Save',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: widget.onChangeRole,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Change role (Designer / Printer)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
