import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nocknock/features/assistant/mascot_tip.dart';
import 'package:nocknock/features/assistant/nock_face.dart';

export 'mascot_tip.dart';
export 'nock_face.dart' show NockFace;

/// A chat opening expands from the mascot's actual position, including after a drag.
class AssistantChatRoute<T> extends PageRouteBuilder<T> {
  static final _origins = Expando<Offset>();
  static final _returns = Expando<ValueNotifier<int>>();

  static ValueNotifier<int> _returnSignal(MascotPosition host) =>
      _returns[host.position] ??= ValueNotifier(0);

  static void recordOrigin(BuildContext context, Offset origin) {
    _origins[Navigator.of(context)] = origin;
  }

  factory AssistantChatRoute({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    final navigator = Navigator.of(context);
    final origin = _origins[navigator];
    _origins[navigator] = null;
    final size = MediaQuery.sizeOf(context);
    final anchor = origin == null
        ? Alignment.bottomRight
        : Alignment(
            (origin.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
            (origin.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
          );
    final reduce = MediaQuery.disableAnimationsOf(context);
    final route = AssistantChatRoute<T>._(builder, anchor, reduce);
    final host = context.getInheritedWidgetOfExactType<MascotPosition>();
    if (host != null) {
      final signal = _returnSignal(host);
      // Navigator.push completes at pop; wait until the reverse animation ends.
      unawaited(route.completed.then((_) => signal.value++));
    }
    return route;
  }

  AssistantChatRoute._(WidgetBuilder builder, Alignment anchor, bool reduce)
    : super(
        transitionDuration: reduce
            ? Duration.zero
            : const Duration(milliseconds: 520),
        reverseTransitionDuration: reduce
            ? Duration.zero
            : const Duration(milliseconds: 420),
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (context, animation, _, child) {
          final curved = animation.drive(
            CurveTween(curve: Curves.easeInOutCubic),
          );
          return FadeTransition(
            opacity: animation.drive(
              CurveTween(
                curve: const Interval(0, .85, curve: Curves.easeInOut),
              ),
            ),
            child: ScaleTransition(
              alignment: anchor,
              scale: curved.drive(Tween(begin: .12, end: 1.0)),
              child: AnimatedBuilder(
                animation: curved,
                child: child,
                builder: (_, child) => ClipRRect(
                  borderRadius: BorderRadius.circular(32 * (1 - curved.value)),
                  child: child,
                ),
              ),
            ),
          );
        },
      );
}

class MascotPosition extends InheritedWidget {
  const MascotPosition({
    super.key,
    required this.position,
    required this.dismissedTips,
    required this.onDismiss,
    this.onPlaced,
    required super.child,
  });
  final ValueNotifier<Alignment?> position;
  final Set<String> dismissedTips;
  final ValueChanged<MascotTip> onDismiss;
  final ValueChanged<Alignment>? onPlaced;
  @override
  bool updateShouldNotify(MascotPosition oldWidget) =>
      position != oldWidget.position;
}

/// Keep the assistant with its route and use the actual create button as its
/// default dock. A user placement always wins over scrolling or moving the FAB.
class AssistantSurface extends StatefulWidget {
  const AssistantSurface({
    super.key,
    required this.child,
    required this.onOpen,
    required this.label,
    this.hint,
    this.dock,
    this.topic = MascotTopic.general,
    this.scope,
  });
  final Widget child;
  final void Function([MascotTip? tip])? onOpen;
  final String label;
  final String? hint, scope;
  final GlobalKey? dock;
  final MascotTopic topic;
  @override
  State<AssistantSurface> createState() => _AssistantSurfaceState();
}

class _AssistantSurfaceState extends State<AssistantSurface> {
  final _overlay = GlobalKey();
  final _dock = ValueNotifier<Rect?>(null);
  bool _scheduled = false;
  void _measureDock(MascotPosition host) {
    if (_scheduled || widget.dock == null) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || host.position.value != null) return;
      final overlay = _overlay.currentContext?.findRenderObject();
      final target = widget.dock?.currentContext?.findRenderObject();
      Rect? location;
      if (overlay is RenderBox &&
          target is RenderBox &&
          overlay.hasSize &&
          target.hasSize &&
          target.attached &&
          overlay.attached) {
        final rect = MatrixUtils.transformRect(
          target.getTransformTo(overlay),
          Offset.zero & target.size,
        );
        if (rect.isFinite && (Offset.zero & overlay.size).overlaps(rect)) {
          location = rect;
        }
      }
      _dock.value = location;
      // Follow layout, scrolling, entrance animations and snack bars only on
      // frames Flutter was already going to draw. This never requests a frame.
      if (overlay != null) _measureDock(host);
    });
  }

  @override
  void dispose() {
    _dock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = context.dependOnInheritedWidgetOfExactType<MascotPosition>();
    final visible =
        host != null &&
        widget.onOpen != null &&
        ModalRoute.isCurrentOf(context) != false &&
        MediaQuery.viewInsetsOf(context).bottom == 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (visible)
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: LayoutBuilder(
                  key: _overlay,
                  builder: (context, bounds) {
                    if (host.position.value == null) _measureDock(host);
                    return _FloatingNock(
                      key: ValueKey((
                        widget.topic,
                        widget.scope ?? widget.label,
                      )),
                      host: host,
                      dock: _dock,
                      hasDock: widget.dock != null,
                      topic: widget.topic,
                      label: widget.label,
                      hint: widget.hint,
                      onOpen: widget.onOpen!,
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FloatingNock extends StatefulWidget {
  const _FloatingNock({
    super.key,
    required this.host,
    required this.dock,
    required this.hasDock,
    required this.topic,
    required this.label,
    required this.hint,
    required this.onOpen,
  });
  final MascotPosition host;
  final ValueNotifier<Rect?> dock;
  final bool hasDock;
  final MascotTopic topic;
  final String label;
  final String? hint;
  final void Function([MascotTip? tip]) onOpen;
  @override
  State<_FloatingNock> createState() => _FloatingNockState();
}

class _FloatingNockState extends State<_FloatingNock>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _size = 52.0;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final _tapBounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  bool _opening = false;
  Timer? _faceTimer, _tipTimer;
  NockExpression _expression = NockExpression.wink;
  final _shown = <MascotTip>{};
  MascotTip? _tip;
  bool _dragging = false,
      _active = false,
      _reduceMotion = false,
      _accessible = false;
  Offset? _dragOrigin;
  late final ValueNotifier<int> _returnSignal;

  void _bounceOnReturn() {
    if (!mounted || !_active || _reduceMotion) return;
    _motion.reset();
    _expression = NockExpression.delighted;
    unawaited(_tapBounce.forward(from: 0));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _returnSignal = AssistantChatRoute._returnSignal(widget.host);
    _returnSignal.addListener(_bounceOnReturn);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    _accessible = MediaQuery.accessibleNavigationOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _motion.reset();
      _faceTimer?.cancel();
      if (!reduce && _active) _scheduleFace();
    }
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _syncActivity(lifecycle: state);

  void _syncActivity({AppLifecycleState? lifecycle}) {
    final state = lifecycle ?? WidgetsBinding.instance.lifecycleState;
    final active =
        (state == null || state == AppLifecycleState.resumed) &&
        TickerMode.valuesOf(context).enabled;
    if (active == _active) return;
    _active = active;
    if (active) {
      _scheduleFace();
      _scheduleTip(const Duration(seconds: 6));
    } else {
      _faceTimer?.cancel();
      _tipTimer?.cancel();
      _motion.reset();
      if (_tip != null || _dragging) {
        setState(() {
          _tip = null;
          _dragging = false;
        });
      }
    }
  }

  void _play(NockExpression expression) {
    if (_reduceMotion || !_active) return;
    _expression = expression;
    _motion.forward(from: 0);
  }

  void _scheduleFace() {
    _faceTimer?.cancel();
    if (!_active || _reduceMotion) return;
    _faceTimer = Timer(const Duration(seconds: 4), () {
      if (!_dragging) {
        final expressions = NockExpression.values;
        _play(expressions[(_expression.index + 1) % expressions.length]);
      }
      _scheduleFace();
    });
  }

  void _scheduleTip(Duration delay) {
    _tipTimer?.cancel();
    if (!_active || _dragging) return;
    final available = widget.topic.tips
        .where((tip) => !widget.host.dismissedTips.contains(tip.name))
        .toList();
    if (available.isEmpty) return;
    // Keep offering help after the first round, while respecting every X.
    // The quiet interval below separates suggestions so they never pile up.
    if (available.every(_shown.contains)) _shown.clear();
    final next = available.firstWhere((tip) => !_shown.contains(tip));
    _tipTimer = Timer(delay, () {
      setState(() {
        _tip = next;
        _shown.add(next);
      });
      _play(NockExpression.delighted);
      if (!_accessible) {
        _tipTimer = Timer(const Duration(seconds: 10), _hideTip);
      }
    });
  }

  void _hideTip({bool dismiss = false}) {
    if (dismiss && _tip != null) widget.host.onDismiss(_tip!);
    setState(() => _tip = null);
    _scheduleTip(const Duration(seconds: 35));
  }

  @override
  void dispose() {
    _faceTimer?.cancel();
    _tipTimer?.cancel();
    _returnSignal.removeListener(_bounceOnReturn);
    _tapBounce.dispose();
    _motion.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth, height = constraints.maxHeight;
        final dx = math.max(0.0, width - _size),
            dy = math.max(0.0, height - _size);
        return ListenableBuilder(
          listenable: Listenable.merge([widget.host.position, widget.dock]),
          builder: (context, _) {
            final saved = widget.host.position.value;
            final target = widget.hasDock ? widget.dock.value : null;
            final dock = target != null && target.top >= _size + 8
                ? target
                : null;
            final defaultX = dock == null ? dx - 6 : dock.center.dx - _size / 2;
            final defaultY = dock == null ? dy - 70 : dock.top - _size - 8;
            final x = (saved == null ? defaultX : (saved.x + 1) / 2 * dx).clamp(
              0.0,
              dx,
            );
            final y = (saved == null ? defaultY : (saved.y + 1) / 2 * dy).clamp(
              0.0,
              dy,
            );
            Future<void> openChat([MascotTip? tip]) async {
              if (_opening || _dragging) return;
              _opening = true;
              _hideTip();
              _faceTimer?.cancel();
              _motion.reset();
              _expression = NockExpression.delighted;
              try {
                if (!_reduceMotion) await _tapBounce.forward(from: 0).orCancel;
              } on TickerCanceled {
                return;
              }
              if (!mounted || !context.mounted) return;
              _opening = false;
              if (!_active || ModalRoute.isCurrentOf(context) == false) {
                _scheduleFace();
                return;
              }
              _scheduleFace();
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && box.hasSize) {
                AssistantChatRoute.recordOrigin(
                  context,
                  box.localToGlobal(Offset(x + _size / 2, y + _size / 2)),
                );
              }
              widget.onOpen(tip);
            }

            return Stack(
              children: [
                Positioned(
                  left: x,
                  top: y,
                  width: _size,
                  height: _size,
                  child: Semantics(
                    button: true,
                    label: 'Abrir chat de Nock. ${widget.label}',
                    child: Tooltip(
                      message:
                          widget.hint ?? 'Hablar con Nock · ${widget.label}',
                      child: GestureDetector(
                        onPanStart: (_) {
                          if (_opening) return;
                          _dragOrigin = Offset(x, y);
                          _tipTimer?.cancel();
                          setState(() {
                            _dragging = true;
                            _tip = null;
                          });
                          _play(NockExpression.curious);
                        },
                        onPanUpdate: (e) {
                          if (_opening) return;
                          final p = (_dragOrigin ?? Offset(x, y)) + e.delta;
                          _dragOrigin = Offset(
                            p.dx.clamp(0.0, dx),
                            p.dy.clamp(0.0, dy),
                          );
                          widget.host.position.value = Alignment(
                            dx == 0 ? 0 : _dragOrigin!.dx / dx * 2 - 1,
                            dy == 0 ? 0 : _dragOrigin!.dy / dy * 2 - 1,
                          );
                        },
                        onPanEnd: (_) => _finishDrag(),
                        onPanCancel: _finishDrag,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            RepaintBoundary(
                              child: AnimatedBuilder(
                                animation: Listenable.merge([
                                  _motion,
                                  _tapBounce,
                                ]),
                                builder: (context, _) {
                                  final bounce = math.sin(
                                    math.pi * _tapBounce.value,
                                  );
                                  final bouncing = _tapBounce.isAnimating;
                                  final amount = bouncing
                                      ? bounce
                                      : math.sin(math.pi * _motion.value);
                                  return Transform.translate(
                                    offset: Offset(
                                      0,
                                      bouncing ? -9 * bounce : -6 * amount,
                                    ),
                                    child: Transform.rotate(
                                      angle:
                                          .12 *
                                          math.sin(2 * math.pi * _motion.value),
                                      child: Transform.scale(
                                        scaleX: bouncing
                                            ? 1 - .06 * bounce
                                            : 1 + .045 * amount,
                                        scaleY: bouncing
                                            ? 1 + .08 * bounce
                                            : 1 + .045 * amount,
                                        child: NockFace(
                                          size: _size,
                                          expression: _expression,
                                          amount: amount,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                key: const ValueKey('nock-mascot'),
                                customBorder: const CircleBorder(),
                                onTap: openChat,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                CustomSingleChildLayout(
                  delegate: _BubblePosition(
                    Offset(x + _size / 2, y + _size / 2),
                    _size,
                  ),
                  child: AnimatedSwitcher(
                    duration: _reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 320),
                    reverseDuration: _reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final tail = _BubblePosition(
                        Offset(x + _size / 2, y + _size / 2),
                        _size,
                      ).tailFor(Size(width, height));
                      final anchor = switch (tail) {
                        AxisDirection.right => Alignment.centerRight,
                        AxisDirection.left => Alignment.centerLeft,
                        AxisDirection.up => Alignment.topCenter,
                        AxisDirection.down => Alignment.bottomCenter,
                      };
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          alignment: anchor,
                          scale: animation.drive(Tween(begin: .78, end: 1.0)),
                          child: IgnorePointer(
                            ignoring: child.key != ValueKey(_tip),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: _tip == null
                        ? const SizedBox.shrink()
                        : _TipBubble(
                            key: ValueKey(_tip),
                            tip: _tip!,
                            tail: _BubblePosition(
                              Offset(x + _size / 2, y + _size / 2),
                              _size,
                            ).tailFor(Size(width, height)),
                            onChoose: () => openChat(_tip),
                            onClose: () => _hideTip(dismiss: true),
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _finishDrag() {
    if (!_dragging) return;
    _dragOrigin = null;
    setState(() => _dragging = false);
    final point = widget.host.position.value;
    if (point != null) widget.host.onPlaced?.call(point);
    _scheduleTip(const Duration(seconds: 12));
  }
}

class _BubblePosition extends SingleChildLayoutDelegate {
  const _BubblePosition(this.center, this.diameter);
  final Offset center;
  final double diameter;
  double get gap => diameter / 2 - 4;
  double _space(Size size) => math.max(center.dx, size.width - center.dx) - gap;
  AxisDirection tailFor(Size size) => _space(size) >= 145
      ? (center.dx > size.width / 2 ? AxisDirection.right : AxisDirection.left)
      : (center.dy > size.height / 2 ? AxisDirection.down : AxisDirection.up);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest, space = _space(size);
    return BoxConstraints(
      maxWidth: math.min(240.0, space >= 145 ? space : size.width),
      maxHeight: size.height,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = center.dx > size.width / 2;
    final beside = _space(size) >= 145;
    final x = beside
        ? (left ? center.dx - gap - childSize.width : center.dx + gap)
        : center.dx - childSize.width / 2;
    final y = beside
        // Center the balloon itself; the close control reserves 36 px above it.
        ? center.dy - (childSize.height + 36) / 2
        : center.dy > size.height / 2
        ? center.dy - gap - childSize.height
        : center.dy + gap;
    return Offset(
      x.clamp(0.0, size.width - childSize.width),
      y.clamp(0.0, size.height - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_BubblePosition old) =>
      center != old.center || diameter != old.diameter;
}

class _TipBubble extends StatelessWidget {
  const _TipBubble({
    super.key,
    required this.tip,
    required this.tail,
    required this.onChoose,
    required this.onClose,
  });
  final MascotTip tip;
  final AxisDirection tail;
  final VoidCallback onChoose, onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final inset = EdgeInsets.fromLTRB(
      tail == AxisDirection.left ? 10 : 0,
      tail == AxisDirection.up ? 10 : 0,
      tail == AxisDirection.right ? 10 : 0,
      tail == AxisDirection.down ? 10 : 0,
    );
    return Stack(
      children: [
        Padding(
          // Reserve room for the floating close control outside the speech balloon.
          padding: const EdgeInsets.only(top: 36),
          child: CustomPaint(
            painter: _SpeechBalloonPainter(
              tail: tail,
              fill: colors.surfaceContainerHigh.withValues(alpha: .84),
              border: colors.primary.withValues(alpha: .35),
            ),
            child: Padding(
              padding: inset,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onChoose,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Text(
                        tip.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: colors.onSurface, height: 1.35),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            tooltip: 'Cerrar sugerencia',
            onPressed: onClose,
            style: IconButton.styleFrom(
              minimumSize: const Size(32, 32),
              maximumSize: const Size(32, 32),
              padding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              foregroundColor: colors.onSurface.withValues(alpha: .8),
            ),
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              shadows: [
                Shadow(
                  color: colors.surface.withValues(alpha: .9),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeechBalloonPainter extends CustomPainter {
  const _SpeechBalloonPainter({
    required this.tail,
    required this.fill,
    required this.border,
  });
  final AxisDirection tail;
  final Color fill, border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      tail == AxisDirection.left ? 10 : 0,
      tail == AxisDirection.up ? 10 : 0,
      size.width - (tail == AxisDirection.right ? 10 : 0),
      size.height - (tail == AxisDirection.down ? 10 : 0),
    ).deflate(.75);
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20)));
    final triangle = Path();
    switch (tail) {
      case AxisDirection.right:
        triangle
          ..moveTo(rect.right - 1, rect.center.dy - 9)
          ..lineTo(size.width, rect.center.dy + 5)
          ..lineTo(rect.right - 1, rect.center.dy + 9);
      case AxisDirection.left:
        triangle
          ..moveTo(rect.left + 1, rect.center.dy - 9)
          ..lineTo(0, rect.center.dy + 5)
          ..lineTo(rect.left + 1, rect.center.dy + 9);
      case AxisDirection.up:
        triangle
          ..moveTo(rect.center.dx - 9, rect.top + 1)
          ..lineTo(rect.center.dx + 5, 0)
          ..lineTo(rect.center.dx + 9, rect.top + 1);
      case AxisDirection.down:
        triangle
          ..moveTo(rect.center.dx - 9, rect.bottom - 1)
          ..lineTo(rect.center.dx + 5, size.height)
          ..lineTo(rect.center.dx + 9, rect.bottom - 1);
    }
    triangle.close();
    final balloon = Path.combine(PathOperation.union, body, triangle);
    canvas.drawPath(balloon, Paint()..color = fill);
    canvas.drawPath(
      balloon,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SpeechBalloonPainter oldDelegate) =>
      tail != oldDelegate.tail ||
      fill != oldDelegate.fill ||
      border != oldDelegate.border;
}
