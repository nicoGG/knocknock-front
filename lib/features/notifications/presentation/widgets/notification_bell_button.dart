import 'dart:math' as math;

import 'package:flutter/material.dart';

class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({
    required this.unreadCount,
    required this.onPressed,
    super.key,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _attentionController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  int get _unreadCount => widget.unreadCount < 0 ? 0 : widget.unreadCount;

  bool get _hasUnread => _unreadCount > 0;

  String get _displayCount => _unreadCount > 99 ? '99+' : '$_unreadCount';

  String get _tooltip => _hasUnread
      ? '$_unreadCount ${_unreadCount == 1 ? 'notificación sin leer' : 'notificaciones sin leer'}'
      : 'Notificaciones';

  @override
  void initState() {
    super.initState();
    if (_hasUnread) _attentionController.forward();
  }

  @override
  void didUpdateWidget(NotificationBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasUnread && widget.unreadCount != oldWidget.unreadCount) {
      _attentionController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _attentionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return IconButton(
      tooltip: _tooltip,
      onPressed: widget.onPressed,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        maximumSize: const Size.square(44),
        foregroundColor: _hasUnread ? colors.primary : colors.onSurfaceVariant,
        hoverColor: colors.primary.withValues(alpha: 0.1),
        highlightColor: colors.primary.withValues(alpha: 0.14),
      ),
      icon: AnimatedBuilder(
        animation: _attentionController,
        builder: (context, _) {
          final progress = reduceMotion ? 1.0 : _attentionController.value;
          final remaining = 1 - Curves.easeOutCubic.transform(progress);
          final bellAngle = _hasUnread
              ? math.sin(progress * math.pi * 5) * 0.15 * remaining
              : 0.0;
          final badgeProgress = Curves.easeOutBack.transform(
            (progress / 0.72).clamp(0.0, 1.0),
          );
          final badgeScale = reduceMotion || !_hasUnread
              ? 1.0
              : 0.68 + (0.32 * badgeProgress);
          final haloScale = 0.88 + (0.34 * progress);
          final haloOpacity = _hasUnread
              ? (math.sin(progress * math.pi) * 0.24).clamp(0.0, 0.24)
              : 0.0;

          return SizedBox.square(
            dimension: 30,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (_hasUnread && !reduceMotion)
                  Transform.scale(
                    key: const ValueKey('notification-bell-halo'),
                    scale: haloScale,
                    child: Opacity(
                      opacity: haloOpacity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.primary, width: 1.5),
                        ),
                        child: const SizedBox.square(dimension: 30),
                      ),
                    ),
                  ),
                Transform.rotate(
                  key: const ValueKey('notification-bell-rotation'),
                  angle: bellAngle,
                  alignment: Alignment.topCenter,
                  child: Icon(
                    _hasUnread
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: 25,
                  ),
                ),
                Positioned(
                  top: -7,
                  right: -9,
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: _hasUnread
                        ? Transform.scale(
                            key: const ValueKey('notification-badge-scale'),
                            scale: badgeScale,
                            child: Container(
                              key: const ValueKey('notification-count-badge'),
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.error,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: colors.surface,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.error.withValues(alpha: 0.3),
                                    blurRadius: 7,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: AnimatedSwitcher(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                child: Text(
                                  _displayCount,
                                  key: ValueKey(
                                    'notification-count-$_displayCount',
                                  ),
                                  style: TextStyle(
                                    color: colors.onError,
                                    fontSize: 10,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('notification-count-empty'),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
