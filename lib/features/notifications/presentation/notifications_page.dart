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
  final Set<String> _selectedIds = {};
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  void _toggleSelection(String notificationId) {
    setState(() {
      _isSelecting = true;
      if (!_selectedIds.add(notificationId)) {
        _selectedIds.remove(notificationId);
      }
      if (_selectedIds.isEmpty) _isSelecting = false;
    });
  }

  void _startSelection() {
    setState(() => _isSelecting = true);
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelecting = false;
    });
  }

  void _toggleSelectAll(List<AppNotification> notifications) {
    setState(() {
      final allIds = notifications.map((notification) => notification.id);
      if (_selectedIds.length == notifications.length) {
        _selectedIds.clear();
        _isSelecting = false;
      } else {
        _selectedIds
          ..clear()
          ..addAll(allIds);
        _isSelecting = _selectedIds.isNotEmpty;
      }
    });
  }

  Future<void> _refresh() async {
    await widget.controller.load();
    if (!mounted) return;
    final availableIds = widget.controller.notifications
        .map((notification) => notification.id)
        .toSet();
    setState(() {
      _selectedIds.retainAll(availableIds);
      if (_selectedIds.isEmpty) _isSelecting = false;
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0 || widget.controller.isDeletingNotifications) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text(
          count == 1
              ? '¿Eliminar esta notificación?'
              : '¿Eliminar $count notificaciones?',
        ),
        content: Text(
          count == 1
              ? 'Se eliminará de tu cuenta y no podrás recuperarla.'
              : 'Se eliminarán de tu cuenta y no podrás recuperarlas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-notifications-button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ids = Set<String>.from(_selectedIds);
    final deleted = await widget.controller.deleteNotifications(ids);
    if (!mounted) return;
    if (deleted) {
      _clearSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Notificación eliminada.'
                : '$count notificaciones eliminadas.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.message ??
                'No pudimos eliminar las notificaciones.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectionTitle = switch (_selectedIds.length) {
      0 => 'Seleccionar',
      1 => '1 seleccionada',
      final count => '$count seleccionadas',
    };
    return Scaffold(
      appBar: AppBar(
        leading: _isSelecting
            ? IconButton(
                tooltip: 'Cancelar selección',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          _isSelecting ? selectionTitle : 'Notificaciones',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: _isSelecting
            ? [
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final notifications = widget.controller.notifications;
                    final allSelected =
                        notifications.isNotEmpty &&
                        _selectedIds.length == notifications.length;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const ValueKey(
                            'select-all-notifications-button',
                          ),
                          tooltip: allSelected
                              ? 'Quitar selección'
                              : 'Seleccionar todas',
                          onPressed: notifications.isEmpty
                              ? null
                              : () => _toggleSelectAll(notifications),
                          icon: Icon(
                            allSelected
                                ? Icons.deselect_rounded
                                : Icons.select_all_rounded,
                          ),
                        ),
                        if (widget.controller.isDeletingNotifications)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          IconButton(
                            key: const ValueKey(
                              'delete-selected-notifications-button',
                            ),
                            tooltip: 'Eliminar seleccionadas',
                            onPressed: _selectedIds.isEmpty
                                ? null
                                : _deleteSelected,
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        const SizedBox(width: 8),
                      ],
                    );
                  },
                ),
              ]
            : [
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey(
                          'start-notifications-selection-button',
                        ),
                        tooltip: 'Seleccionar notificaciones',
                        onPressed: widget.controller.notifications.isEmpty
                            ? null
                            : _startSelection,
                        icon: const Icon(Icons.checklist_rounded),
                      ),
                      TextButton(
                        onPressed: widget.controller.unreadCount == 0
                            ? null
                            : widget.controller.markAllRead,
                        child: const Text('Marcar leídas'),
                      ),
                    ],
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
                onRefresh: _refresh,
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
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                itemCount: notifications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final notification = notifications[index];
                  return _NotificationTile(
                    key: ValueKey('notification-${notification.id}'),
                    notification: notification,
                    isSelected: _selectedIds.contains(notification.id),
                    isSelectionMode: _isSelecting,
                    onLongPress: () => _toggleSelection(notification.id),
                    onTap: () async {
                      if (_isSelecting) {
                        _toggleSelection(notification.id);
                        return;
                      }
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
  const _NotificationTile({
    required this.notification,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final AppNotification notification;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _accent(notification.type, colorScheme);
    final borderRadius = BorderRadius.circular(18);
    return Semantics(
      selected: isSelected,
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.7)
            : notification.isRead
            ? colorScheme.surfaceContainerLow
            : accent.withValues(alpha: 0.11),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: isSelected
              ? BorderSide(color: colorScheme.primary, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: isSelected
                      ? colorScheme.primary
                      : accent.withValues(alpha: 0.17),
                  foregroundColor: isSelected ? colorScheme.onPrimary : accent,
                  child: Icon(
                    isSelected ? Icons.check_rounded : _icon(notification.type),
                    size: 21,
                  ),
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
                          if (!notification.isRead && !isSelectionMode)
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
      ),
    );
  }

  static IconData _icon(AppNotificationType type) => switch (type) {
    AppNotificationType.collaboratorJoined => Icons.group_add_rounded,
    AppNotificationType.noteCreated => Icons.note_add_outlined,
    AppNotificationType.noteUpdated => Icons.edit_note_rounded,
    AppNotificationType.noteDeleted => Icons.delete_outline_rounded,
    AppNotificationType.taskAssigned => Icons.assignment_ind_outlined,
    AppNotificationType.reminder => Icons.alarm_rounded,
  };

  static Color _accent(AppNotificationType type, ColorScheme colors) =>
      switch (type) {
        AppNotificationType.collaboratorJoined => const Color(0xFF3568C8),
        AppNotificationType.noteCreated => const Color(0xFF2C8B57),
        AppNotificationType.noteUpdated => colors.primary,
        AppNotificationType.noteDeleted => colors.error,
        AppNotificationType.taskAssigned => const Color(0xFF7A5BC7),
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
