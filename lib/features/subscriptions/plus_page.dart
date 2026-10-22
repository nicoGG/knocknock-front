import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:url_launcher/url_launcher.dart';

import 'plus_service.dart';

import 'package:nocknock/core/widgets/ambient_page_background.dart';

class PlusPage extends StatefulWidget {
  const PlusPage({required this.auth, super.key});
  final AuthRepository auth;
  @override
  State<PlusPage> createState() => _PlusPageState();
}

class _PlusPageState extends State<PlusPage> {
  late final PlusService _service = PlusService(widget.auth);
  StreamSubscription<dynamic>? _authChanges;
  PlusStatus? _status;
  List<PlusPackage> _packages = [];
  String? _message;
  bool _busy = false;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _service.addListener(_billingUpdated);
    _service.start();
    final uid = widget.auth.currentUser?.id;
    _authChanges = widget.auth.authStateChanges.listen((user) {
      if (user?.id != uid && mounted) Navigator.of(context).pop();
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _service.removeListener(_billingUpdated);
    unawaited(_authChanges?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.auth.currentUser == null) return;
    await _perform(() async {
      final status = await _service.status();
      final packages = status.purchasesEnabled && _service.storeAvailable
          ? await _service.packages()
          : <PlusPackage>[];
      if (!mounted) return;
      setState(() {
        _status = status;
        _packages = packages;
      });
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'No pudimos completar la operación. Revisa tu conexión e inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _billingUpdated() {
    if (!mounted) return;
    setState(() {
      _status = _service.latestStatus ?? _status;
      _message = _service.message;
    });
  }

  Future<void> _restore() => _perform(() async {
    await _service.restore();
    if (mounted) {
      setState(
        () => _message = 'Buscando compras en Google Play. Se verificará su titularidad con tu cuenta de NockNock.',
      );
    }
  });

  Future<void> _openLegal(String raw) => _perform(() async {
    final url = Uri.tryParse(raw);
    if (url == null ||
        url.scheme != 'https' ||
        !await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw StateError('No pudimos abrir la información.');
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _status?.active == true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        // Extra painted height keeps both edges covered during parallax.
        Positioned(
          top: -48,
          bottom: -96,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: _scroll,
            child: const AmbientPageBackground(),
            builder: (context, child) => Transform.translate(
              offset: Offset(
                0,
                reduceMotion
                    ? 0
                    : -(_scroll.hasClients ? _scroll.offset : 0).clamp(0, 500) *
                          .08,
              ),
              child: child,
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: AnimatedBuilder(
              animation: _scroll,
              child: const Text(
                'NockNock Plus',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
              ),
              builder: (context, child) {
                final progress =
                    ((_scroll.hasClients ? _scroll.offset : 0) / 180).clamp(
                      0.0,
                      1.0,
                    );
                return Transform.translate(
                  offset: Offset(0, reduceMotion ? 0 : -4 * progress),
                  child: Transform.scale(
                    scale: reduceMotion ? 1 : 1 - .04 * progress,
                    child: Opacity(opacity: 1 - progress, child: child),
                  ),
                );
              },
            ),
            flexibleSpace: AnimatedBuilder(
              animation: _scroll,
              builder: (context, _) {
                final progress =
                    ((_scroll.hasClients ? _scroll.offset : 0) / 150).clamp(
                      0.0,
                      1.0,
                    );
                return ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: 16 * progress,
                      sigmaY: 16 * progress,
                    ),
                    child: ColoredBox(
                      color: theme.colorScheme.surface.withValues(
                        alpha: .72 * progress,
                      ),
                    ),
                  ),
                );
              },
            ),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          body: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ListView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
                      24,
                      MediaQuery.paddingOf(context).bottom + 32,
                    ),
                    children:
                        [
                              AnimatedBuilder(
                                animation: _scroll,
                                child: _PlusHero(active: active),
                                builder: (context, child) {
                                  final offset =
                                      (_scroll.hasClients ? _scroll.offset : 0)
                                          .clamp(0.0, 380.0);
                                  return Transform.translate(
                                    offset: Offset(
                                      0,
                                      reduceMotion ? 0 : offset * .22,
                                    ),
                                    child: Opacity(
                                      opacity: reduceMotion
                                          ? 1
                                          : (1 - offset / 650).clamp(0.0, 1.0),
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 24),
                              _PlusSurface(
                                highlighted: true,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Más espacio para lo que comparten',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 20),
                                    const _PlusBenefit(
                                      Icons.view_agenda_rounded,
                                      '50 listas propias',
                                      'Para la casa, los proyectos y todo lo que viene.',
                                    ),
                                    const _PlusBenefit(
                                      Icons.group_rounded,
                                      'Hasta 6 personas por lista',
                                      'Tú y 5 invitados. Una sola suscripción.',
                                    ),
                                    const _PlusBenefit(
                                      Icons.attach_file_rounded,
                                      '2 GiB para tus adjuntos',
                                      'Fotos y archivos cifrados entre tus listas.',
                                    ),
                                    const _PlusBenefit(
                                      Icons.history_rounded,
                                      'Vuelve a una versión anterior',
                                      'Hasta 10 versiones de los últimos 90 días.',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                active
                                    ? 'Tu plan Plus'
                                    : 'Elige cómo organizarte',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _packages.isEmpty
                                    ? 'Precios previstos en Chile · Próximamente'
                                    : 'Precios de Google Play',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 14),
                              if (_packages.isEmpty && !active) ...[
                                const _PlusPrice(
                                  annual: true,
                                  price: r'$34.990 CLP',
                                  preview: true,
                                ),
                                const SizedBox(height: 10),
                                const _PlusPrice(
                                  annual: false,
                                  price: r'$3.990 CLP',
                                  preview: true,
                                ),
                              ],
                              if (!active)
                                for (final package in _packages) ...[
                                  _PlusPrice(
                                    annual: package.annual,
                                    price: package.product.price,
                                    onTap: _busy
                                        ? null
                                        : () => _perform(
                                            () => _service.purchase(package),
                                          ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              const SizedBox(height: 16),
                              const Text(
                                'Tú das el Plus. Todos lo disfrutan. Los beneficios se aplican a las listas que tú creas; tus invitados no necesitan pagar.',
                              ),
                              const SizedBox(height: 24),
                              if (_status case final status?) ...[
                                _PlusSurface(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tu espacio actual',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 16),
                                      _PlusUsage(
                                        label: 'Listas propias',
                                        value:
                                            '${status.ownedLists} / ${status.listLimit}',
                                        progress:
                                            status.ownedLists /
                                            status.listLimit,
                                      ),
                                      const SizedBox(height: 16),
                                      _PlusUsage(
                                        label: 'Adjuntos',
                                        value:
                                            '${(status.storageBytes / 1048576).toStringAsFixed(1)} / ${(status.storageLimit / 1048576).round()} MiB',
                                        progress:
                                            status.storageBytes /
                                            status.storageLimit,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text(
                                    '¿Qué pasa con mis listas actuales?',
                                  ),
                                  children: const [
                                    Padding(
                                      padding: EdgeInsets.only(bottom: 16),
                                      child: Text(
                                        'Tus listas y colaboradores actuales se conservan. Si superas un límite, puedes seguir usándolos; se restringen las nuevas ampliaciones. Las invitaciones pendientes reservan una plaza. La papelera ocupa espacio. Participar en listas de otra persona no cambia tu plan personal.',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (_status?.purchasesEnabled != true)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Text(
                                    'Próximamente. Estamos preparando Plus. Por ahora no se realizan cobros en esta versión.',
                                  ),
                                ),
                              if (_status?.purchasesEnabled == true &&
                                  !_service.storeAvailable)
                                const Text(
                                  'La contratación de Plus está disponible desde la versión Android habilitada para Google Play.',
                                ),
                              if (_status?.purchasesEnabled == true &&
                                  _service.storeAvailable &&
                                  _packages.isEmpty &&
                                  !active &&
                                  !_busy)
                                const Text(
                                  'Los planes aún no están disponibles en Google Play para esta instalación. Puedes volver a consultar el estado.',
                                ),
                              if (widget.auth.currentUser == null)
                                const Text(
                                  'Inicia sesión desde tu perfil para consultar tu suscripción.',
                                ),
                              if (_packages.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Suscripción con renovación automática. El importe mostrado se cobra '
                                    'por cada período. Puedes cancelar la renovación desde la tienda.',
                                  ),
                                ),
                              if (_status?.termsUrl.isNotEmpty == true)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _openLegal(_status!.termsUrl),
                                  child: const Text(
                                    'Condiciones de la suscripción',
                                  ),
                                ),
                              if (_status?.privacyUrl.isNotEmpty == true)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _openLegal(_status!.privacyUrl),
                                  child: const Text('Política de privacidad'),
                                ),
                              const SizedBox(height: 12),
                              if (_service.storeAvailable &&
                                  widget.auth.currentUser != null)
                                TextButton(
                                  onPressed: _busy ? null : _restore,
                                  child: const Text('Restaurar compras'),
                                ),
                              if (active)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _perform(() async {
                                          final url = _service.storeAvailable
                                              ? await _service.managementUrl()
                                              : null;
                                          if (url == null ||
                                              !await launchUrl(
                                                url,
                                                mode: LaunchMode
                                                    .externalApplication,
                                              )) {
                                            if (mounted) {
                                              setState(
                                                () => _message = 'Abre la tienda donde contrataste Plus para gestionar tu suscripción.',
                                              );
                                            }
                                          }
                                        }),
                                  child: const Text(
                                    'Gestionar suscripción en la tienda',
                                  ),
                                ),
                              if (_busy)
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              if (_message != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(
                                    _message!,
                                    semanticsLabel: _message,
                                  ),
                                ),
                              if (!_busy && widget.auth.currentUser != null)
                                TextButton(
                                  onPressed: _load,
                                  child: const Text('Actualizar estado'),
                                ),
                            ]
                            .asMap()
                            .entries
                            .map(
                              (entry) => _PlusEntrance(
                                key: ValueKey('plus-section-${entry.key}'),
                                order: entry.key,
                                child: entry.value,
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlusHero extends StatelessWidget {
  const _PlusHero({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        const _PlusIllustration(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: colors.primary.withValues(alpha: .2)),
          ),
          child: Text(
            'UN PLUS PARA COMPARTIR',
            style: TextStyle(
              color: colors.primary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          active ? 'Tu mundo tiene Plus.' : 'Más juntos. Más posibilidades.',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Una persona paga por sus listas compartidas.\nLos invitados participan gratis.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        if (active) ...[
          const SizedBox(height: 14),
          Chip(
            avatar: Icon(
              Icons.verified_rounded,
              size: 18,
              color: colors.primary,
            ),
            label: const Text('Tu cuenta tiene NockNock Plus activo.'),
          ),
        ],
      ],
    );
  }
}

class _PlusSurface extends StatelessWidget {
  const _PlusSurface({required this.child, this.highlighted = false});
  final Widget child;
  final bool highlighted;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surfaceContainerLow,
        gradient: highlighted
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    c.primary.withValues(alpha: .12),
                    c.surfaceContainerLow,
                  ),
                  c.surfaceContainerLow,
                ],
              )
            : null,
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: c.primary.withValues(alpha: .07),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: highlighted
              ? c.primary.withValues(alpha: .24)
              : c.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: child,
    );
  }
}

class _PlusBenefit extends StatelessWidget {
  const _PlusBenefit(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: c.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlusPrice extends StatelessWidget {
  const _PlusPrice({
    required this.annual,
    required this.price,
    this.preview = false,
    this.onTap,
  });
  final bool annual, preview;
  final String price;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: annual ? c.primaryContainer : c.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: annual ? c.primary.withValues(alpha: .6) : c.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      annual ? 'Anual' : 'Mensual',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (annual)
                    Flexible(
                      child: Text(
                        preview ? 'AHORRA 27%' : 'PLAN ANUAL',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: c.onPrimaryContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$price / ${annual ? 'año' : 'mes'}',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                annual && preview
                    ? r'Equivale a $2.916 CLP al mes · Un pago anual'
                    : annual
                    ? 'Un pago cada año'
                    : 'Un pago cada mes',
                style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
              ),
              if (!preview) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onTap,
                  child: Text(
                    annual ? 'Elegir Plus anual' : 'Elegir Plus mensual',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlusUsage extends StatelessWidget {
  const _PlusUsage({
    required this.label,
    required this.value,
    required this.progress,
  });
  final String label, value;
  final double progress;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        value: progress.isFinite ? progress.clamp(0, 1) : 0,
        minHeight: 6,
        borderRadius: BorderRadius.circular(6),
      ),
    ],
  );
}

class _PlusIllustration extends StatefulWidget {
  const _PlusIllustration();
  @override
  State<_PlusIllustration> createState() => _PlusIllustrationState();
}

class _PlusIllustrationState extends State<_PlusIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _float.stop();
      _float.value = 0;
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        height: 148,
        width: 280,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    c.primary.withValues(alpha: .22),
                    c.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 24,
              top: 26,
              child: _FloatingPlus(
                animation: _float,
                phase: 0,
                distance: 5,
                tilt: .025,
                child: Transform.rotate(
                  angle: -.18,
                  child: _MiniPlusCard(
                    icon: Icons.checklist_rounded,
                    color: c.tertiary,
                    label: 'En equipo',
                  ),
                ),
              ),
            ),
            Positioned(
              right: 24,
              top: 20,
              child: _FloatingPlus(
                animation: _float,
                phase: 2.2,
                distance: 6,
                tilt: .03,
                child: Transform.rotate(
                  angle: .16,
                  child: _MiniPlusCard(
                    icon: Icons.favorite_outline_rounded,
                    color: c.primary,
                    label: 'En familia',
                  ),
                ),
              ),
            ),
            _FloatingPlus(
              animation: _float,
              phase: 4.1,
              distance: 4,
              tilt: .018,
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c.primary, c.tertiary],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: c.surface.withValues(alpha: .6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.primary.withValues(alpha: .3),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 38,
                  color: c.onPrimary,
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              child: _FloatingPlus(
                animation: _float,
                phase: 1.3,
                distance: 3,
                tilt: .012,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: c.outlineVariant.withValues(alpha: .5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final icon in [
                        Icons.person_rounded,
                        Icons.person_rounded,
                        Icons.person_add_alt_1_rounded,
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Icon(icon, size: 18, color: c.primary),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlusCard extends StatelessWidget {
  const _MiniPlusCard({
    required this.icon,
    required this.color,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      width: 100,
      height: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: .13),
          c.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Container(
            height: 4,
            width: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps its completed entrance when scrolling away or refreshing billing state.
class _PlusEntrance extends StatefulWidget {
  const _PlusEntrance({required this.order, required this.child, super.key});
  final int order;
  final Widget child;
  @override
  State<_PlusEntrance> createState() => _PlusEntranceState();
}

class _PlusEntranceState extends State<_PlusEntrance>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final delay = widget.order.clamp(0, 6) * 45;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : Duration(milliseconds: 520 + delay),
      curve: Interval(delay / (520 + delay), 1, curve: Curves.easeOutCubic),
      child: widget.child,
      builder: (context, value, child) => Opacity(
        opacity: reduceMotion ? 1 : value,
        child: Transform.translate(
          offset: Offset(0, reduceMotion ? 0 : 22 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class _FloatingPlus extends StatelessWidget {
  const _FloatingPlus({
    required this.animation,
    required this.phase,
    required this.distance,
    required this.tilt,
    required this.child,
  });
  final Animation<double> animation;
  final double phase, distance, tilt;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final angle = animation.value * math.pi * 2 + phase;
        return Transform.translate(
          offset: Offset(
            math.cos(angle) * distance * .35,
            math.sin(angle) * distance,
          ),
          child: Transform.rotate(angle: math.sin(angle) * tilt, child: child),
        );
      },
    );
  }
}
