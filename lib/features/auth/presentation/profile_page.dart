import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';
import 'package:nocknock/core/widgets/ambient_page_background.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({required this.themeController, super.key});

  final AppThemeController themeController;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ValueNotifier<double> _appBarScrollProgress = ValueNotifier(0);

  @override
  void dispose() {
    _appBarScrollProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: AmbientPageBackground(
            key: ValueKey('profile-ambient-background'),
          ),
        ),
        Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text(
              'Perfil',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.45,
              ),
            ),
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
                    key: const ValueKey('profile-appbar-bottom-fade'),
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.62, 1],
                      colors: [Colors.white, Colors.white, Colors.transparent],
                    ).createShader(bounds),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 18 * progress,
                        sigmaY: 18 * progress,
                      ),
                      child: ColoredBox(
                        key: const ValueKey('profile-appbar-background'),
                        color: colors.surface.withValues(
                          alpha: 0.74 * progress,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          body: NotificationListener<ScrollNotification>(
            onNotification: _updateAppBarFade,
            child: ListView(
              key: const ValueKey('profile-scroll-view'),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.paddingOf(context).top + kToolbarHeight + 14,
                20,
                MediaQuery.paddingOf(context).bottom + 40,
              ),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ProfileCard(themeController: widget.themeController),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _updateAppBarFade(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final nextProgress = (notification.metrics.pixels / 64).clamp(0.0, 1.0);
    if ((_appBarScrollProgress.value - nextProgress).abs() > 0.001) {
      _appBarScrollProgress.value = nextProgress;
    }
    return false;
  }
}

class AuthAvatar extends StatelessWidget {
  const AuthAvatar({required this.user, this.size = 40, super.key});

  final AppUser? user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final photoUrl = user?.photoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final fallback = ColoredBox(
      key: const ValueKey('profile-icon'),
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          size: size * 0.55,
          color: colorScheme.onSurface,
        ),
      ),
    );

    return Semantics(
      image: hasPhoto,
      label: hasPhoto ? 'Foto de perfil' : 'Perfil',
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        child: hasPhoto
            ? Image.network(
                photoUrl,
                key: const ValueKey('profile-photo'),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class ProfileCard extends StatefulWidget {
  const ProfileCard({required this.themeController, super.key});

  final AppThemeController themeController;

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  bool _isWorking = false;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AuthRepository>();
    return StreamBuilder<AppUser?>(
      stream: repository.authStateChanges,
      initialData: repository.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: user == null
              ? _SignedOutProfile(
                  key: const ValueKey('signed-out-profile'),
                  isWorking: _isWorking,
                  onSignIn: () => _run(repository.signInWithGoogle),
                  themeController: widget.themeController,
                )
              : _SignedInProfile(
                  key: const ValueKey('signed-in-profile'),
                  user: user,
                  isWorking: _isWorking,
                  onSignOut: () => _run(repository.signOut),
                  onDeleteAccount: () => _confirmAccountDeletion(repository),
                  themeController: widget.themeController,
                ),
        );
      },
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _isWorking = true);
    try {
      await action();
    } on AuthFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos completar la acción.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _confirmAccountDeletion(AuthRepository repository) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar tu cuenta?'),
        content: const Text(
          'Se eliminarán permanentemente tu acceso, tus listas, notas, '
          'notificaciones y dispositivos registrados. Tu perfil se quitará '
          'de las listas compartidas; el contenido que otras personas '
          'necesiten conservar puede permanecer de forma anónima.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-account-button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(repository.deleteAccount);
  }
}

class _SignedOutProfile extends StatelessWidget {
  const _SignedOutProfile({
    required this.isWorking,
    required this.onSignIn,
    required this.themeController,
    super.key,
  });

  final bool isWorking;
  final VoidCallback onSignIn;
  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileHeroCard(
          title: 'Tu espacio en NockNock',
          subtitle:
              'Inicia sesión con Google para proteger y sincronizar tus notas.',
          footer: Column(
            children: [
              FilledButton.icon(
                key: const ValueKey('google-sign-in-button'),
                onPressed: isWorking ? null : onSignIn,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: isWorking
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const _GoogleMark(),
                label: const Text(
                  'Iniciar sesión con Google',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tus notas locales permanecen en este dispositivo hasta que inicies sesión.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.52),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        _ProfileThemePicker(themeController: themeController),
        const SizedBox(height: 26),
        const _ProfileSectionTitle('AL INICIAR SESIÓN'),
        const SizedBox(height: 10),
        const _ProfileDetailsCard(
          children: [
            _ProfileDetailRow(
              icon: Icons.enhanced_encryption_outlined,
              title: 'Cifrado de extremo a extremo',
              subtitle:
                  'Al iniciar sesión, tus listas y notas se cifran antes de sincronizarse.',
            ),
            _ProfileCardDivider(),
            _ProfileDetailRow(
              icon: Icons.cloud_sync_outlined,
              title: 'Sincronización segura',
              subtitle: 'Accede a tus listas desde tus dispositivos.',
            ),
            _ProfileCardDivider(),
            _ProfileDetailRow(
              icon: Icons.group_outlined,
              title: 'Listas compartidas',
              subtitle: 'Colabora y recibe asignaciones en tiempo real.',
            ),
            _ProfileCardDivider(),
            _ProfileDetailRow(
              icon: Icons.notifications_none_rounded,
              title: 'Recordatorios conectados',
              subtitle: 'Mantén tus tareas y avisos asociados a tu cuenta.',
            ),
          ],
        ),
      ],
    );
  }
}

class _SignedInProfile extends StatelessWidget {
  const _SignedInProfile({
    required this.user,
    required this.isWorking,
    required this.onSignOut,
    required this.onDeleteAccount,
    required this.themeController,
    super.key,
  });

  final AppUser user;
  final bool isWorking;
  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;
  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileHeroCard(
          user: user,
          title: user.displayName,
          subtitle: user.email,
        ),
        const SizedBox(height: 26),
        _ProfileThemePicker(themeController: themeController),
        const SizedBox(height: 26),
        const _ProfileSectionTitle('PRIVACIDAD Y CUENTA'),
        const SizedBox(height: 10),
        const _ProfileDetailsCard(
          children: [
            _ProfileDetailRow(
              icon: Icons.cloud_done_outlined,
              title: 'Sincronización activa',
              subtitle: 'Tus listas y notas están conectadas con tu cuenta.',
            ),
            _ProfileCardDivider(),
            _ProfileDetailRow(
              icon: Icons.enhanced_encryption_outlined,
              title: 'Cifrado de extremo a extremo',
              subtitle:
                  'Tus listas y notas se cifran antes de sincronizarse. Solo tú y tus colaboradores autorizados pueden leerlas.',
            ),
            _ProfileCardDivider(),
            _ProfileDetailRow(
              icon: Icons.lock_outline_rounded,
              title: 'Acceso con Google',
              subtitle: 'Tu identidad se protege con el acceso de Google.',
            ),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const ValueKey('sign-out-button'),
          onPressed: isWorking ? null : onSignOut,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: isWorking
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout_rounded, size: 19),
          label: const Text(
            'Cerrar sesión',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 30),
        const _ProfileSectionTitle('ZONA DE RIESGO'),
        const SizedBox(height: 10),
        _DeleteAccountCard(
          isWorking: isWorking,
          onDeleteAccount: onDeleteAccount,
        ),
      ],
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.title,
    required this.subtitle,
    this.user,
    this.footer,
  });

  final String title;
  final String subtitle;
  final AppUser? user;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final signedIn = user != null;
    return Container(
      key: const ValueKey('profile-hero-card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: signedIn ? 0.18 : 0.13),
            colorScheme.surfaceContainerHigh,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _FloatingProfileIcons(signedIn: signedIn)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AuthAvatar(user: user, size: 78),
                      if (signedIn)
                        Positioned(
                          right: -2,
                          bottom: 1,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: const Color(0xFF35A765),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.45,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.62),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  if (footer case final footer?) ...[
                    const SizedBox(height: 18),
                    SizedBox(width: double.infinity, child: footer),
                  ],
                  if (signedIn) ...[
                    const SizedBox(height: 14),
                    Container(
                      key: const ValueKey('profile-connection-badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF35A765).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_done_outlined,
                            color: Color(0xFF35A765),
                            size: 15,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'CUENTA CONECTADA',
                            style: TextStyle(
                              color: Color(0xFF35A765),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingProfileIcons extends StatefulWidget {
  const _FloatingProfileIcons({required this.signedIn});

  final bool signedIn;

  @override
  State<_FloatingProfileIcons> createState() => _FloatingProfileIconsState();
}

class _FloatingProfileIconsState extends State<_FloatingProfileIcons>
    with SingleTickerProviderStateMixin {
  static const _icons = [
    _FloatingProfileIconSpec(
      id: 'note',
      icon: Icons.sticky_note_2_outlined,
      alignment: Alignment(-0.83, -0.72),
      phase: 0,
      travelX: 7,
      travelY: 10,
      bubbleSize: 46,
      accent: true,
    ),
    _FloatingProfileIconSpec(
      id: 'list',
      icon: Icons.checklist_rounded,
      alignment: Alignment(0.82, -0.58),
      phase: 1.35,
      travelX: 6,
      travelY: 8,
      bubbleSize: 42,
    ),
    _FloatingProfileIconSpec(
      id: 'lock',
      icon: Icons.lock_outline_rounded,
      alignment: Alignment(-0.88, 0.34),
      phase: 2.7,
      travelX: 8,
      travelY: 7,
      bubbleSize: 40,
    ),
    _FloatingProfileIconSpec(
      id: 'cloud',
      icon: Icons.cloud_done_outlined,
      alignment: Alignment(0.87, 0.3),
      phase: 4.05,
      travelX: 9,
      travelY: 10,
      bubbleSize: 46,
      accent: true,
    ),
    _FloatingProfileIconSpec(
      id: 'shield',
      icon: Icons.shield_outlined,
      alignment: Alignment(0.63, 0.88),
      phase: 5.25,
      travelX: 7,
      travelY: 8,
      bubbleSize: 38,
    ),
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 0.18;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final orbit = _controller.value * math.pi * 2;
            return Stack(
              children: [
                for (final spec in _icons)
                  Align(
                    alignment: spec.alignment,
                    child: Transform.translate(
                      key: ValueKey('profile-floating-icon-${spec.id}'),
                      offset: Offset(
                        math.sin(orbit + spec.phase) * spec.travelX,
                        math.cos(orbit + spec.phase) * spec.travelY,
                      ),
                      child: Transform.rotate(
                        angle: math.sin(orbit + spec.phase) * 0.08,
                        child: Transform.scale(
                          scale: 1 + (math.cos(orbit + spec.phase) * 0.035),
                          child: _FloatingProfileIcon(
                            spec: spec,
                            signedIn: widget.signedIn,
                            colorScheme: colorScheme,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FloatingProfileIcon extends StatelessWidget {
  const _FloatingProfileIcon({
    required this.spec,
    required this.signedIn,
    required this.colorScheme,
  });

  final _FloatingProfileIconSpec spec;
  final bool signedIn;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final color = spec.accent ? colorScheme.primary : colorScheme.onSurface;
    final backgroundAlpha = spec.accent
        ? (signedIn ? 0.15 : 0.12)
        : (signedIn ? 0.07 : 0.055);
    final foregroundAlpha = spec.accent
        ? (signedIn ? 0.68 : 0.58)
        : (signedIn ? 0.36 : 0.3);
    return Container(
      width: spec.bubbleSize,
      height: spec.bubbleSize,
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundAlpha),
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: backgroundAlpha + 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(
        spec.icon,
        size: spec.bubbleSize * 0.48,
        color: color.withValues(alpha: foregroundAlpha),
      ),
    );
  }
}

class _FloatingProfileIconSpec {
  const _FloatingProfileIconSpec({
    required this.id,
    required this.icon,
    required this.alignment,
    required this.phase,
    required this.travelX,
    required this.travelY,
    required this.bubbleSize,
    this.accent = false,
  });

  final String id;
  final IconData icon;
  final Alignment alignment;
  final double phase;
  final double travelX;
  final double travelY;
  final double bubbleSize;
  final bool accent;
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.25,
        ),
      ),
    );
  }
}

class _ProfileThemePicker extends StatelessWidget {
  const _ProfileThemePicker({required this.themeController});

  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _ProfileSectionTitle('TEMA DE COLOR')),
              Icon(
                Icons.swipe_rounded,
                size: 15,
                color: colorScheme.onSurface.withValues(alpha: 0.42),
              ),
              const SizedBox(width: 4),
              Text(
                'Desliza',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.48),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final optionWidth = (constraints.maxWidth - (spacing * 3)) / 4;
                const options = [
                  (theme: AppColorTheme.sunset, label: 'Atardecer'),
                  (theme: AppColorTheme.ocean, label: 'Océano'),
                  (theme: AppColorTheme.forest, label: 'Bosque'),
                  (theme: AppColorTheme.violet, label: 'Violeta'),
                  (theme: AppColorTheme.cherry, label: 'Cereza'),
                  (theme: AppColorTheme.amber, label: 'Ámbar'),
                  (theme: AppColorTheme.mint, label: 'Menta'),
                  (theme: AppColorTheme.midnight, label: 'Noche'),
                  (theme: AppColorTheme.coral, label: 'Coral'),
                  (theme: AppColorTheme.gold, label: 'Dorado'),
                  (theme: AppColorTheme.lime, label: 'Lima'),
                  (theme: AppColorTheme.turquoise, label: 'Turquesa'),
                  (theme: AppColorTheme.sky, label: 'Celeste'),
                  (theme: AppColorTheme.indigo, label: 'Índigo'),
                  (theme: AppColorTheme.lavender, label: 'Lavanda'),
                  (theme: AppColorTheme.graphite, label: 'Grafito'),
                ];
                return SizedBox(
                  height: 80,
                  child: ListView.separated(
                    key: const ValueKey('profile-color-theme-list'),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: options.length,
                    separatorBuilder: (_, _) => const SizedBox(width: spacing),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return SizedBox(
                        width: optionWidth,
                        child: _ProfileColorThemeOption(
                          key: ValueKey(
                            'profile-color-theme-${option.theme.name}',
                          ),
                          colorTheme: option.theme,
                          label: option.label,
                          selected: themeController.colorTheme == option.theme,
                          onTap: () =>
                              themeController.setColorTheme(option.theme),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          const _ProfileSectionTitle('MODO'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ProfileThemeOption(
                    key: const ValueKey('profile-theme-system'),
                    icon: Icons.brightness_auto_outlined,
                    label: 'Sistema',
                    selected: themeController.themeMode == ThemeMode.system,
                    onTap: () => themeController.setThemeMode(ThemeMode.system),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ProfileThemeOption(
                    key: const ValueKey('profile-theme-light'),
                    icon: Icons.light_mode_outlined,
                    label: 'Claro',
                    selected: themeController.themeMode == ThemeMode.light,
                    onTap: () => themeController.setThemeMode(ThemeMode.light),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ProfileThemeOption(
                    key: const ValueKey('profile-theme-dark'),
                    icon: Icons.dark_mode_outlined,
                    label: 'Oscuro',
                    selected: themeController.themeMode == ThemeMode.dark,
                    onTap: () => themeController.setThemeMode(ThemeMode.dark),
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

class _ProfileColorThemeOption extends StatelessWidget {
  const _ProfileColorThemeOption({
    required this.colorTheme,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final AppColorTheme colorTheme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tema de color $label${selected ? ', seleccionado' : ''}',
      child: Material(
        color: selected
            ? colorTheme.seedColor.withValues(alpha: 0.14)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(
            color: selected
                ? colorTheme.seedColor.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.38),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colorTheme.seedColor, colorTheme.secondaryColor],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorTheme.seedColor.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? colorTheme.seedColor
                        : colorScheme.onSurface,
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileThemeOption extends StatelessWidget {
  const _ProfileThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? colorScheme.primary : colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tema $label${selected ? ', seleccionado' : ''}',
      child: Material(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.13)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.34)
                : colorScheme.outlineVariant.withValues(alpha: 0.38),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: selected ? 0.15 : 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: foreground),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileDetailsCard extends StatelessWidget {
  const _ProfileDetailsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileCardDivider extends StatelessWidget {
  const _ProfileCardDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 54,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.7),
    );
  }
}

class _ProfileDetailRow extends StatelessWidget {
  const _ProfileDetailRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.58),
                    fontSize: 12,
                    height: 1.3,
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

class _DeleteAccountCard extends StatelessWidget {
  const _DeleteAccountCard({
    required this.isWorking,
    required this.onDeleteAccount,
  });

  final bool isWorking;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.delete_forever_outlined,
                  color: colorScheme.error,
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'Eliminar tu cuenta',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            'Esta acción elimina permanentemente tu acceso y tus datos. No se puede deshacer.',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.65),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            key: const ValueKey('delete-account-button'),
            onPressed: isWorking ? null : onDeleteAccount,
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text(
              'Eliminar cuenta',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
