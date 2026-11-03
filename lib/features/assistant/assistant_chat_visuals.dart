import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The same warm translucent material as NockNock's sheets. Blur is reserved
/// for fixed panels; messages use a tint so long conversations scroll smoothly.
class ChatGlass extends StatelessWidget {
  const ChatGlass({
    super.key,
    required this.child,
    this.accent,
    this.radius = const BorderRadius.all(Radius.circular(24)),
    this.frosted = false,
    this.highlighted = false,
  });

  final Widget child;
  final BorderRadius radius;
  final Color? accent;
  final bool frosted, highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final tint = accent ?? colors.surfaceContainer;
    final translucent = frosted && !MediaQuery.highContrastOf(context);
    final panel = AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: highlighted
              ? colors.primary
              : Colors.white.withValues(alpha: dark ? .18 : .76),
          width: 1.2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              tint.withValues(alpha: .32),
              dark ? colors.surfaceContainerHigh : Colors.white,
            ).withValues(alpha: translucent ? .62 : .91),
            Color.alphaBlend(
              tint.withValues(alpha: .54),
              colors.surface,
            ).withValues(alpha: translucent ? .48 : .84),
          ],
        ),
      ),
      child: child,
    );
    if (!frosted) return panel;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .24 : .13),
            blurRadius: 16,
            blurStyle: BlurStyle.outer,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: panel,
        ),
      ),
    );
  }
}

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble(
    this.text, {
    super.key,
    this.mine = false,
    this.action,
  });
  final String text;
  final bool mine;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: Radius.circular(mine ? 22 : 6),
      bottomRight: Radius.circular(mine ? 6 : 22),
    );
    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: .91,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ChatGlass(
            accent: mine ? colors.primaryContainer : null,
            radius: radius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 10, 15, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mine ? 'Tú' : 'Nock',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SelectableText(
                    text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MediaQuery.disableAnimationsOf(context)
          ? bubble
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: bubble,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 9 * (1 - value)),
                  child: child,
                ),
              ),
            ),
    );
  }
}

/// Three rising dots for a reply, or narrow sound bars while dictating.
class ChatActivity extends StatefulWidget {
  const ChatActivity({super.key, this.voice = false});
  final bool voice;

  @override
  State<ChatActivity> createState() => _ChatActivityState();
}

class _ChatActivityState extends State<ChatActivity>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = widget.voice ? 'Escuchando…' : 'Nock está escribiendo…';
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _motion,
              builder: (context, _) => SizedBox(
                width: 26,
                height: 22,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < (widget.voice ? 4 : 3); i++)
                      Transform.translate(
                        offset: Offset(0, widget.voice ? 0 : -2 * _wave(i)),
                        child: Container(
                          width: widget.voice ? 3 : 5,
                          height: widget.voice ? 5 + 10 * _wave(i) : 5,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  double _wave(int i) =>
      (math.sin(_motion.value * 2 * math.pi - i * 1.2) + 1) / 2;
}
