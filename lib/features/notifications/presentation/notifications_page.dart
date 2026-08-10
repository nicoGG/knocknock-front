import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/notifications/domain/app_notification.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.controller, super.key});

  final NotificationsController controller;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  final Set<String> _selectedIds = {};
  final Set<String> _swipeDeletingIds = {};
  final ValueNotifier<double> _appBarScrollProgress = ValueNotifier(0);
  bool _isSelecting = false;
  late final AnimationController _ambientController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.load());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ambientController
        ..stop()
        ..value = 0.32;
    } else if (!_ambientController.isAnimating) {
      _ambientController.repeat();
    }
  }

  @override
  void dispose() {
    _appBarScrollProgress.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  bool _updateAppBarFade(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final nextProgress = (notification.metrics.pixels / 64).clamp(0.0, 1.0);
    if ((_appBarScrollProgress.value - nextProgress).abs() > 0.001) {
      _appBarScrollProgress.value = nextProgress;
    }
    return false;
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
      _swipeDeletingIds.retainAll(availableIds);
      if (_selectedIds.isEmpty) _isSelecting = false;
    });
  }

  void _dismissBySwipe(AppNotification notification) {
    setState(() {
      _swipeDeletingIds.add(notification.id);
      _selectedIds.remove(notification.id);
      if (_selectedIds.isEmpty) _isSelecting = false;
    });
    unawaited(_deleteSwipedNotification(notification));
  }

  Future<bool> _confirmSwipeDelete(AppNotification notification) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('swipe-delete-notification-dialog'),
        icon: Icon(
          Icons.delete_sweep_outlined,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('¿Eliminar esta notificación?'),
        content: Text(
          '“${notification.title}” se eliminará de tu cuenta y no podrás recuperarla.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-swipe-delete-notification-button'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-swipe-delete-notification-button'),
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
    return confirmed ?? false;
  }

  Future<void> _deleteSwipedNotification(AppNotification notification) async {
    final deleted = await widget.controller.deleteNotifications({
      notification.id,
    });
    if (!mounted) return;
    setState(() => _swipeDeletingIds.remove(notification.id));
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted
                ? 'Notificación eliminada.'
                : widget.controller.message ??
                      'No pudimos eliminar la notificación.',
          ),
        ),
      );
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
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              count == 1
                  ? 'Notificación eliminada.'
                  : '$count notificaciones eliminadas.',
            ),
          ),
        );
    } else {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final notifications = widget.controller.notifications;
        final visibleNotifications = notifications
            .where(
              (notification) => !_swipeDeletingIds.contains(notification.id),
            )
            .toList(growable: false);
        final unreadCount = widget.controller.unreadCount;
        final allSelected =
            visibleNotifications.isNotEmpty &&
            visibleNotifications.every(
              (notification) => _selectedIds.contains(notification.id),
            );
        final colorScheme = Theme.of(context).colorScheme;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: const ValueKey('notifications-animated-background'),
                    painter: _NotificationsBackdropPainter(
                      animation: _ambientController,
                      colorScheme: colorScheme,
                      unreadCount: unreadCount,
                      brightness: Theme.of(context).brightness,
                    ),
                  ),
                ),
              ),
            ),
            Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                flexibleSpace: ValueListenableBuilder<double>(
                  valueListenable: _appBarScrollProgress,
                  builder: (context, rawProgress, _) {
                    final progress = Curves.easeOutCubic.transform(
                      rawProgress.clamp(0.0, 1.0),
                    );
                    return ClipRect(
                      child: ShaderMask(
                        key: const ValueKey('notifications-appbar-bottom-fade'),
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, 0.62, 1],
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                        ).createShader(bounds),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: 18 * progress,
                            sigmaY: 18 * progress,
                          ),
                          child: DecoratedBox(
                            key: const ValueKey(
                              'notifications-appbar-background',
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(
                                alpha: 0.72 * progress,
                              ),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
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
                        IconButton(
                          key: const ValueKey(
                            'select-all-notifications-button',
                          ),
                          tooltip: allSelected
                              ? 'Quitar selección'
                              : 'Seleccionar todas',
                          onPressed: visibleNotifications.isEmpty
                              ? null
                              : () => _toggleSelectAll(visibleNotifications),
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
                      ]
                    : [
                        IconButton(
                          key: const ValueKey(
                            'start-notifications-selection-button',
                          ),
                          tooltip: 'Seleccionar notificaciones',
                          onPressed: visibleNotifications.isEmpty
                              ? null
                              : _startSelection,
                          icon: const Icon(Icons.checklist_rounded),
                        ),
                        IconButton(
                          key: const ValueKey(
                            'mark-all-notifications-read-button',
                          ),
                          tooltip: 'Marcar todas como leídas',
                          onPressed: unreadCount == 0
                              ? null
                              : widget.controller.markAllRead,
                          icon: const Icon(Icons.done_all_rounded),
                        ),
                        const SizedBox(width: 8),
                      ],
              ),
              body: _NotificationsContentFade(
                topInset: MediaQuery.paddingOf(context).top,
                scrollProgress: _appBarScrollProgress,
                child: SafeArea(
                  bottom: false,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _updateAppBarFade,
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child:
                          widget.controller.isLoading &&
                              visibleNotifications.isEmpty
                          ? _NotificationsLoadingState(
                              key: const ValueKey('notifications-loading'),
                              animation: _ambientController,
                            )
                          : visibleNotifications.isEmpty
                          ? RefreshIndicator(
                              key: const ValueKey('notifications-empty'),
                              onRefresh: _refresh,
                              child: _EmptyNotificationsState(
                                animation: _ambientController,
                              ),
                            )
                          : RefreshIndicator(
                              key: const ValueKey('notifications-list'),
                              onRefresh: _refresh,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  kToolbarHeight + 10,
                                  16,
                                  32,
                                ),
                                itemCount: visibleNotifications.length + 1,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return _NotificationsOverview(
                                      animation: _ambientController,
                                      unreadCount: unreadCount,
                                      totalCount: visibleNotifications.length,
                                    );
                                  }
                                  final notification =
                                      visibleNotifications[index - 1];
                                  return _SwipeableNotificationTile(
                                    key: ValueKey(
                                      'notification-${notification.id}',
                                    ),
                                    notification: notification,
                                    enabled:
                                        !_isSelecting &&
                                        !widget
                                            .controller
                                            .isDeletingNotifications,
                                    onConfirmDismiss: () =>
                                        _confirmSwipeDelete(notification),
                                    onDismissed: () =>
                                        _dismissBySwipe(notification),
                                    child: _NotificationTile(
                                      notification: notification,
                                      entranceIndex: index - 1,
                                      isSelected: _selectedIds.contains(
                                        notification.id,
                                      ),
                                      isSelectionMode: _isSelecting,
                                      onLongPress: () =>
                                          _toggleSelection(notification.id),
                                      onTap: () async {
                                        if (_isSelecting) {
                                          _toggleSelection(notification.id);
                                          return;
                                        }
                                        await widget.controller.markRead(
                                          notification,
                                        );
                                        if (context.mounted) {
                                          Navigator.pop(context, notification);
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NotificationsContentFade extends StatelessWidget {
  const _NotificationsContentFade({
    required this.topInset,
    required this.scrollProgress,
    required this.child,
  });

  final double topInset;
  final ValueListenable<double> scrollProgress;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: scrollProgress,
    child: child,
    builder: (context, rawProgress, child) {
      final progress = Curves.easeOutCubic.transform(
        rawProgress.clamp(0.0, 1.0),
      );
      final concealedColor = Colors.white.withValues(alpha: 1 - progress);
      return ShaderMask(
        key: const ValueKey('notifications-content-fade'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final fadeStart = ((topInset + kToolbarHeight + 16) / bounds.height)
              .clamp(0.0, 1.0);
          final fadeEnd = ((topInset + kToolbarHeight + 72) / bounds.height)
              .clamp(0.0, 1.0);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, fadeStart, fadeEnd, 1],
            colors: [
              concealedColor,
              concealedColor,
              Colors.white,
              Colors.white,
            ],
          ).createShader(bounds);
        },
        child: child,
      );
    },
  );
}

class _NotificationsBackdropPainter extends CustomPainter {
  _NotificationsBackdropPainter({
    required this.animation,
    required this.colorScheme,
    required this.unreadCount,
    required this.brightness,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final ColorScheme colorScheme;
  final int unreadCount;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final isDark = brightness == Brightness.dark;
    final energy = (0.58 + (unreadCount.clamp(0, 12) / 30)).clamp(0.58, 0.98);
    final baseTop = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.08 : 0.055),
      colorScheme.surface,
    );
    final baseBottom = Color.alphaBlend(
      colorScheme.tertiary.withValues(alpha: isDark ? 0.055 : 0.035),
      colorScheme.surface,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [baseTop, colorScheme.surface, baseBottom],
          stops: const [0, 0.48, 1],
        ).createShader(rect),
    );

    final phase = animation.value * math.pi * 2;
    _paintGlow(
      canvas,
      center: Offset(
        size.width * (0.13 + (0.1 * math.sin(phase))),
        size.height * (0.16 + (0.035 * math.cos(phase * 0.8))),
      ),
      radius: size.shortestSide * 0.78,
      color: colorScheme.primary.withValues(
        alpha: (isDark ? 0.17 : 0.13) * energy,
      ),
    );
    _paintGlow(
      canvas,
      center: Offset(
        size.width * (0.88 + (0.07 * math.cos(phase * 0.7))),
        size.height * (0.48 + (0.08 * math.sin(phase * 0.55))),
      ),
      radius: size.shortestSide * 0.68,
      color: colorScheme.tertiary.withValues(
        alpha: (isDark ? 0.15 : 0.11) * energy,
      ),
    );
    _paintGlow(
      canvas,
      center: Offset(
        size.width * (0.34 + (0.08 * math.sin(phase * 0.42))),
        size.height * (0.9 + (0.035 * math.cos(phase * 0.64))),
      ),
      radius: size.shortestSide * 0.72,
      color: colorScheme.secondary.withValues(
        alpha: (isDark ? 0.1 : 0.075) * energy,
      ),
    );

    final ribbon = Path()
      ..moveTo(-size.width * 0.15, size.height * 0.28)
      ..cubicTo(
        size.width * (0.22 + (0.04 * math.sin(phase))),
        size.height * 0.2,
        size.width * (0.62 + (0.05 * math.cos(phase))),
        size.height * 0.39,
        size.width * 1.15,
        size.height * 0.29,
      );
    canvas.drawPath(
      ribbon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = colorScheme.primary.withValues(alpha: isDark ? 0.12 : 0.08),
    );
  }

  void _paintGlow(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _NotificationsBackdropPainter oldDelegate) =>
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.unreadCount != unreadCount ||
      oldDelegate.brightness != brightness;
}

class _NotificationsOverview extends StatelessWidget {
  const _NotificationsOverview({
    required this.animation,
    required this.unreadCount,
    required this.totalCount,
  });

  final Animation<double> animation;
  final int unreadCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headline = unreadCount == 0
        ? 'Todo bajo control'
        : unreadCount == 1
        ? '1 notificación pendiente'
        : '$unreadCount notificaciones pendientes';
    final supporting = unreadCount == 0
        ? 'Ya revisaste toda tu actividad reciente.'
        : 'Tienes novedades esperando por ti.';
    return Container(
      key: const ValueKey('notifications-overview-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              colors.primary.withValues(alpha: isDark ? 0.28 : 0.17),
              colors.surface,
            ),
            Color.alphaBlend(
              colors.tertiary.withValues(alpha: isDark ? 0.2 : 0.11),
              colors.surface,
            ),
          ],
        ),
        border: Border.all(
          color: colors.primary.withValues(alpha: isDark ? 0.24 : 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: isDark ? 0.12 : 0.1),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final wave = math.sin(animation.value * math.pi * 2);
              return Transform.rotate(
                angle: unreadCount == 0 ? 0 : wave * 0.045,
                child: Transform.scale(
                  scale: 1 + ((wave + 1) * 0.018),
                  child: child,
                ),
              );
            },
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [colors.primary, colors.tertiary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Icon(
                unreadCount == 0
                    ? Icons.done_all_rounded
                    : Icons.notifications_active_rounded,
                color: colors.onPrimary,
                size: 27,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(supporting, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: isDark ? 0.42 : 0.68),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$totalCount',
              semanticsLabel: '$totalCount notificaciones en total',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsLoadingState extends StatelessWidget {
  const _NotificationsLoadingState({required this.animation, super.key});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final shimmer = -1.4 + (animation.value * 2.8);
        final gradient = LinearGradient(
          begin: Alignment(shimmer - 1, -0.5),
          end: Alignment(shimmer + 1, 0.5),
          colors: [
            colors.surfaceContainerLow.withValues(alpha: 0.78),
            colors.primaryContainer.withValues(alpha: 0.56),
            colors.surfaceContainerLow.withValues(alpha: 0.78),
          ],
        );
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 10, 16, 32),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) => Container(
            height: index == 0 ? 104 : 116,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(index == 0 ? 24 : 20),
              gradient: gradient,
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.22),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  const _EmptyNotificationsState({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 72, 24, 32),
      children: [
        AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final wave = math.sin(animation.value * math.pi * 2);
            return Transform.translate(
              offset: Offset(0, wave * 5),
              child: Transform.rotate(angle: wave * 0.025, child: child),
            );
          },
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 126,
                  height: 126,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        colors.primary.withValues(alpha: 0.2),
                        colors.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [colors.primary, colors.tertiary],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.24),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: colors.onPrimary,
                    size: 38,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Todo al día',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Aquí aparecerán tus recordatorios, tareas y novedades compartidas.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: const Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 7,
              runSpacing: 4,
              children: [
                Icon(Icons.swipe_down_alt_rounded, size: 18),
                Text('Desliza para actualizar'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SwipeableNotificationTile extends StatefulWidget {
  const _SwipeableNotificationTile({
    required this.notification,
    required this.enabled,
    required this.onConfirmDismiss,
    required this.onDismissed,
    required this.child,
    super.key,
  });

  final AppNotification notification;
  final bool enabled;
  final Future<bool> Function() onConfirmDismiss;
  final VoidCallback onDismissed;
  final Widget child;

  @override
  State<_SwipeableNotificationTile> createState() =>
      _SwipeableNotificationTileState();
}

class _SwipeableNotificationTileState
    extends State<_SwipeableNotificationTile> {
  static const _dismissThreshold = 0.42;
  final ValueNotifier<double> _progress = ValueNotifier(0);
  bool _thresholdAnnounced = false;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _handleUpdate(DismissUpdateDetails details) {
    _progress.value = details.progress.clamp(0, 1);
    final reachedThreshold = details.progress >= _dismissThreshold;
    if (reachedThreshold && !_thresholdAnnounced) {
      _thresholdAnnounced = true;
      unawaited(HapticFeedback.mediumImpact());
    } else if (!reachedThreshold) {
      _thresholdAnnounced = false;
    }
  }

  void _deleteFromSemantics() {
    unawaited(_confirmAndDeleteFromSemantics());
  }

  Future<void> _confirmAndDeleteFromSemantics() async {
    if (await widget.onConfirmDismiss()) widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      customSemanticsActions: widget.enabled
          ? {
              const CustomSemanticsAction(label: 'Eliminar notificación'):
                  _deleteFromSemantics,
            }
          : const {},
      child: Dismissible(
        key: ValueKey('swipe-${widget.notification.id}'),
        direction: widget.enabled
            ? DismissDirection.endToStart
            : DismissDirection.none,
        dismissThresholds: const {
          DismissDirection.endToStart: _dismissThreshold,
        },
        movementDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 230),
        resizeDuration: reduceMotion ? null : const Duration(milliseconds: 280),
        onUpdate: _handleUpdate,
        confirmDismiss: (_) => widget.onConfirmDismiss(),
        onDismissed: (_) => widget.onDismissed(),
        background: const SizedBox.shrink(),
        secondaryBackground: _SwipeDeleteBackground(
          key: ValueKey('swipe-delete-background-${widget.notification.id}'),
          progress: _progress,
        ),
        child: ValueListenableBuilder<double>(
          valueListenable: _progress,
          child: widget.child,
          builder: (context, progress, child) => Transform.rotate(
            angle: reduceMotion ? 0 : -0.012 * progress,
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: reduceMotion ? 1 : 1 - (0.018 * progress),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground({required this.progress, super.key});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) {
        final reveal = Curves.easeOutCubic.transform(value.clamp(0, 1));
        final ready =
            value >= _SwipeableNotificationTileState._dismissThreshold;
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  colors.errorContainer.withValues(alpha: 0.72),
                  colors.error.withValues(alpha: 0.88 + (0.12 * reveal)),
                ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  right: -36 + (18 * reveal),
                  top: -30,
                  bottom: -30,
                  child: Container(
                    width: 142,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.onError.withValues(
                        alpha: 0.06 + (0.06 * reveal),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Transform.translate(
                      offset: Offset(20 * (1 - reveal), 0),
                      child: Opacity(
                        opacity: reveal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ready ? 'Suelta para eliminar' : 'Eliminar',
                              style: TextStyle(
                                color: colors.onError,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Transform.rotate(
                              angle: (1 - reveal) * -0.35,
                              child: Transform.scale(
                                scale: 0.72 + (0.28 * reveal),
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colors.onError.withValues(
                                      alpha: ready ? 0.24 : 0.15,
                                    ),
                                    border: Border.all(
                                      color: colors.onError.withValues(
                                        alpha: 0.28,
                                      ),
                                    ),
                                  ),
                                  child: Icon(
                                    ready
                                        ? Icons.delete_forever_rounded
                                        : Icons.delete_outline_rounded,
                                    color: colors.onError,
                                    size: 23,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.entranceIndex,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final AppNotification notification;
  final int entranceIndex;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _accent(notification.type, colorScheme);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final borderRadius = BorderRadius.circular(20);
    final surface = colorScheme.surface;
    final startColor = isSelected
        ? Color.alphaBlend(colorScheme.primary.withValues(alpha: 0.24), surface)
        : Color.alphaBlend(
            accent.withValues(alpha: notification.isRead ? 0.035 : 0.12),
            surface,
          );
    final endColor = isSelected
        ? Color.alphaBlend(colorScheme.tertiary.withValues(alpha: 0.2), surface)
        : Color.alphaBlend(
            accent.withValues(alpha: notification.isRead ? 0.015 : 0.055),
            surface,
          );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : Duration(milliseconds: 300 + math.min(entranceIndex * 45, 270)),
      curve: Curves.easeOutCubic,
      builder: (context, entrance, child) => Opacity(
        opacity: entrance,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - entrance)),
          child: child,
        ),
      ),
      child: Semantics(
        selected: isSelected,
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [startColor, endColor],
            ),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : accent.withValues(alpha: notification.isRead ? 0.08 : 0.2),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(
                  alpha: notification.isRead ? 0.035 : 0.11,
                ),
                blurRadius: notification.isRead ? 12 : 22,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: borderRadius,
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isSelected
                              ? [colorScheme.primary, colorScheme.tertiary]
                              : [
                                  accent.withValues(alpha: 0.95),
                                  Color.lerp(
                                    accent,
                                    colorScheme.tertiary,
                                    0.28,
                                  )!,
                                ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(
                        isSelected
                            ? Icons.check_rounded
                            : _icon(notification.type),
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  notification.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    letterSpacing: -0.2,
                                    fontWeight: notification.isRead
                                        ? FontWeight.w700
                                        : FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (!notification.isRead && !isSelectionMode) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'NUEVA',
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            notification.body,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            runSpacing: 8,
                            spacing: 12,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _typeLabel(notification.type),
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.42,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _timeLabel(notification.createdAt),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.55),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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

  static String _typeLabel(AppNotificationType type) => switch (type) {
    AppNotificationType.collaboratorJoined => 'COLABORACIÓN',
    AppNotificationType.noteCreated => 'NUEVA NOTA',
    AppNotificationType.noteUpdated => 'NOTA',
    AppNotificationType.noteDeleted => 'ELIMINADA',
    AppNotificationType.taskAssigned => 'TAREA',
    AppNotificationType.reminder => 'RECORDATORIO',
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
