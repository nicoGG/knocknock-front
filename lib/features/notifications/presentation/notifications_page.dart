import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/notifications/domain/app_notification.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.controller, super.key});

  final NotificationsController controller;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notificaciones',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => TextButton(
              onPressed: widget.controller.unreadCount == 0
                  ? null
                  : widget.controller.markAllRead,
              child: const Text('Marcar leídas'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final notifications = widget.controller.notifications;
            if (widget.controller.isLoading && notifications.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (notifications.isEmpty) {
              return RefreshIndicator(
                onRefresh: widget.controller.load,
                child: ListView(
                  children: const [
                    SizedBox(height: 130),
                    Icon(Icons.notifications_none_rounded, size: 58),
                    SizedBox(height: 16),
                    Text(
                      'Todo al día',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 7),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 36),
                      child: Text(
                        'Aquí verás recordatorios y actividad de tus listas compartidas.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: widget.controller.load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                itemCount: notifications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final notification = notifications[index];
                  return _NotificationTile(
                    notification: notification,
                    onTap: () async {
                      await widget.controller.markRead(notification);
                      if (context.mounted) Navigator.pop(context, notification);
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _accent(notification.type, colorScheme);
    return Material(
      color: notification.isRead
          ? colorScheme.surfaceContainerLow
          : accent.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.17),
                foregroundColor: accent,
                child: Icon(_icon(notification.type), size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: notification.isRead
                                  ? FontWeight.w700
                                  : FontWeight.w900,
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(notification.body),
                    const SizedBox(height: 7),
                    Text(
                      _timeLabel(notification.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _icon(AppNotificationType type) => switch (type) {
    AppNotificationType.collaboratorJoined => Icons.group_add_rounded,
    AppNotificationType.noteCreated => Icons.note_add_outlined,
    AppNotificationType.noteUpdated => Icons.edit_note_rounded,
    AppNotificationType.noteDeleted => Icons.delete_outline_rounded,
    AppNotificationType.reminder => Icons.alarm_rounded,
  };

  static Color _accent(AppNotificationType type, ColorScheme colors) =>
      switch (type) {
        AppNotificationType.collaboratorJoined => const Color(0xFF3568C8),
        AppNotificationType.noteCreated => const Color(0xFF2C8B57),
        AppNotificationType.noteUpdated => colors.primary,
        AppNotificationType.noteDeleted => colors.error,
        AppNotificationType.reminder => const Color(0xFFD47A17),
      };

  static String _timeLabel(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);
    if (difference.inMinutes < 1) return 'Ahora';
    if (difference.inHours < 1) return 'Hace ${difference.inMinutes} min';
    if (difference.inHours < 24) return 'Hace ${difference.inHours} h';
    return DateFormat('dd MMM · HH:mm', 'es').format(local);
  }
}
