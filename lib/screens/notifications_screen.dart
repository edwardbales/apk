import 'package:flutter/material.dart';

import '../services/notification_store.dart';

/// The notification center — opened from the bell in the top bar.
///
/// Lists every "Printing Ready" notification. Opening this page
/// marks them all read, so the bell badge clears.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    NotificationStore.instance.markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = NotificationStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: store.items.isEmpty ? null : store.clearAll,
            child: const Text('Clear all'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none,
                        size: 56, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    const Text('No notifications yet.',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'When the printer operator taps Done on a file you sent, it will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: store.items.map((n) {
                  final job = n.job;
                  return Card(
                    color: Colors.green.withOpacity(0.10),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.green,
                        child: Icon(Icons.check, color: Colors.white),
                      ),
                      title: Text(
                        'Hey ${job.designerName.isEmpty ? 'Designer' : job.designerName}, your design file completely Printing Ready',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                          '${job.fileName}  •  ${job.printer.label}  •  ${job.material}',
                          style:
                              TextStyle(color: scheme.onSurfaceVariant)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Dismiss',
                        onPressed: () => store.dismiss(job.id),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}
