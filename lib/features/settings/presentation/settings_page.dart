import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nocknock/core/widgets/ambient_page_background.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/auth/presentation/profile_page.dart';
import 'package:nocknock/features/notifications/logic/encrypted_notification_content.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.authRepository,
    required this.onOpenProfile,
    required this.onClearLocalData,
    this.notificationsController,
    this.onOpenNotifications,
    super.key,
  });

  final AuthRepository authRepository;
  final VoidCallback onOpenProfile;
  final Future<bool> Function() onClearLocalData;
  final NotificationsController? notificationsController;
  final VoidCallback? onOpenNotifications;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ValueNotifier<double> _appBarScrollProgress = ValueNotifier(0);
  late final Future<String> _appVersion = _loadAppVersion();
  bool _isClearingData = false;
  bool _notificationPreviewsEnabled = true;
  bool _isLoadingPreferences = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

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
        Positioned.fill(
          child: AmbientPageBackground(
            key: const ValueKey('settings-ambient-background'),
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
            title: const Text(
              'Configuración',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.45,
              ),
            ),
            flexibleSpace: ValueListenableBuilder<double>(
              valueListenable: _appBarScrollProgress,
              builder: (context, rawProgress, _) {
                final progress = Curves.easeOutCubic.transform(
                  rawProgress.clamp(0.0, 1.0),
                );
                return ClipRect(
                  child: ShaderMask(
                    key: const ValueKey('settings-appbar-bottom-fade'),
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
                        key: const ValueKey('settings-appbar-background'),
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
            child: StreamBuilder<AppUser?>(
              stream: widget.authRepository.authStateChanges,
              initialData: widget.authRepository.currentUser,
              builder: (context, snapshot) => ListView(
                key: const ValueKey('settings-list'),
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  18,
                  MediaQuery.paddingOf(context).top + kToolbarHeight + 14,
                  18,
                  MediaQuery.paddingOf(context).bottom + 34,
                ),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: _SettingsContent(
                        user: snapshot.data,
                        appVersion: _appVersion,
                        isClearingData: _isClearingData,
                        notificationPreviewsEnabled:
                            _notificationPreviewsEnabled,
                        isLoadingPreferences: _isLoadingPreferences,
                        notificationsController: widget.notificationsController,
                        onOpenProfile: widget.onOpenProfile,
                        onOpenNotifications: widget.onOpenNotifications,
                        onToggleNotificationPreviews:
                            _setNotificationPreviewsEnabled,
                        onClearLocalData: _confirmClearLocalData,
                        onShowPrivacy: _showPrivacyAndSecurity,
                      ),
                    ),
                  ),
                ],
              ),
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

  Future<void> _loadPreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final enabled =
          preferences.getBool(nockNockNotificationPreviewsEnabledKey) ?? true;
      if (!mounted) return;
      setState(() {
        _notificationPreviewsEnabled = enabled;
        _isLoadingPreferences = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingPreferences = false);
    }
  }

  Future<void> _setNotificationPreviewsEnabled(bool enabled) async {
    setState(() => _notificationPreviewsEnabled = enabled);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(
        nockNockNotificationPreviewsEnabledKey,
        enabled,
      );
    } catch (_) {
      // Keep the preference for this session if persistence is unavailable.
    }
  }

  Future<String> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber.trim();
      return build.isEmpty
          ? 'Versión ${info.version}'
          : 'Versión ${info.version} ($build)';
    } catch (_) {
      return 'Versión 1.0.0';
    }
  }

  void _showPrivacyAndSecurity() {
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Privacidad y seguridad',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tus datos cambian de lugar según cómo uses NockNock.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            const _PrivacyDetail(
              icon: Icons.lock_outline_rounded,
              title: 'Cuenta conectada',
              description:
                  'Las listas y notas se cifran en tu dispositivo antes de sincronizarse.',
            ),
            const SizedBox(height: 18),
            const _PrivacyDetail(
              icon: Icons.phone_android_rounded,
              title: 'Modo invitado',
              description:
                  'Las notas permanecen solo en este dispositivo hasta que las elimines.',
            ),
            const SizedBox(height: 18),
            const _PrivacyDetail(
              icon: Icons.visibility_off_outlined,
              title: 'Avisos discretos',
              description:
                  'Puedes ocultar títulos y contenido en las notificaciones del sistema.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearLocalData() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Limpiar los datos locales?'),
        content: const Text(
          'Se eliminarán definitivamente todas las listas y notas creadas '
          'como invitado en este dispositivo. Los datos de tu cuenta no se '
          'verán afectados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-clear-local-data-button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpiar datos'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _isClearingData = true);
    final didClear = await widget.onClearLocalData();
    if (!mounted) return;
    setState(() => _isClearingData = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          didClear
              ? 'Los datos locales fueron eliminados.'
              : 'No pudimos limpiar los datos locales. Inténtalo nuevamente.',
        ),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.user,
    required this.appVersion,
    required this.isClearingData,
    required this.notificationPreviewsEnabled,
    required this.isLoadingPreferences,
    required this.notificationsController,
    required this.onOpenProfile,
    required this.onOpenNotifications,
    required this.onToggleNotificationPreviews,
    required this.onClearLocalData,
    required this.onShowPrivacy,
  });

  final AppUser? user;
  final Future<String> appVersion;
  final bool isClearingData;
  final bool notificationPreviewsEnabled;
  final bool isLoadingPreferences;
  final NotificationsController? notificationsController;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenNotifications;
  final ValueChanged<bool> onToggleNotificationPreviews;
  final VoidCallback onClearLocalData;
  final VoidCallback onShowPrivacy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsHero(user: user),
        const SizedBox(height: 28),
        const _SettingsSectionTitle('CUENTA'),
        const SizedBox(height: 10),
        _SettingsCard(
          child: _SettingsTile(
            key: const ValueKey('settings-profile-button'),
            leading: AuthAvatar(user: user),
            title: 'Perfil y cuenta',
            subtitle: user == null
                ? 'Conecta tu cuenta para sincronizar y proteger tus notas.'
                : 'Conectado como ${user!.email}',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenProfile,
          ),
        ),
        const SizedBox(height: 28),
        const _SettingsSectionTitle('PREFERENCIAS'),
        const SizedBox(height: 10),
        _SettingsCard(
          child: Column(
            children: [
              _SettingsTile(
                key: const ValueKey('settings-appearance-button'),
                leading: const _SettingsIcon(
                  icon: Icons.palette_outlined,
                  tone: _SettingsIconTone.primary,
                ),
                title: 'Apariencia',
                subtitle: 'Elige el color y el modo visual de toda la app.',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onOpenProfile,
              ),
              if (notificationsController != null &&
                  onOpenNotifications != null) ...[
                const _SettingsDivider(),
                ListenableBuilder(
                  listenable: notificationsController!,
                  builder: (context, _) {
                    final unread = notificationsController!.unreadCount;
                    return _SettingsTile(
                      key: const ValueKey('settings-notifications-button'),
                      leading: const _SettingsIcon(
                        icon: Icons.notifications_none_rounded,
                        tone: _SettingsIconTone.tertiary,
                      ),
                      title: 'Centro de notificaciones',
                      subtitle: unread == 0
                          ? 'Recordatorios y actividad de tus listas.'
                          : unread == 1
                          ? 'Tienes 1 novedad pendiente.'
                          : 'Tienes $unread novedades pendientes.',
                      trailing: unread == 0
                          ? const Icon(Icons.chevron_right_rounded)
                          : _UnreadBadge(count: unread),
                      onTap: onOpenNotifications,
                    );
                  },
                ),
              ],
              const _SettingsDivider(),
              _SettingsTile(
                key: const ValueKey('notification-previews-setting'),
                leading: const _SettingsIcon(
                  icon: Icons.visibility_outlined,
                  tone: _SettingsIconTone.secondary,
                ),
                title: 'Vista previa en notificaciones',
                subtitle: notificationPreviewsEnabled
                    ? 'Muestra el contenido en los avisos del sistema.'
                    : 'Oculta títulos y contenido fuera de NockNock.',
                trailing: Switch.adaptive(
                  key: const ValueKey('notification-previews-switch'),
                  value: notificationPreviewsEnabled,
                  onChanged: isLoadingPreferences
                      ? null
                      : onToggleNotificationPreviews,
                ),
                onTap: isLoadingPreferences
                    ? null
                    : () => onToggleNotificationPreviews(
                        !notificationPreviewsEnabled,
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const _SettingsSectionTitle('DATOS EN ESTE DISPOSITIVO'),
        const SizedBox(height: 10),
        _SettingsCard(
          child: Column(
            children: [
              _SettingsTile(
                leading: const _SettingsIcon(
                  icon: Icons.storage_rounded,
                  tone: _SettingsIconTone.secondary,
                ),
                title: 'Almacenamiento local',
                subtitle: user == null
                    ? 'Aquí se guardan las listas y notas que creas como invitado.'
                    : 'Conserva una copia local para abrir tus notas con rapidez.',
              ),
              const _SettingsDivider(),
              _SettingsTile(
                key: const ValueKey('clear-local-data-button'),
                enabled: !isClearingData,
                leading: isClearingData
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const _SettingsIcon(
                        icon: Icons.delete_sweep_outlined,
                        tone: _SettingsIconTone.danger,
                      ),
                title: 'Limpiar datos locales',
                subtitle: 'No elimina las notas guardadas en tu cuenta.',
                titleColor: Theme.of(context).colorScheme.error,
                onTap: onClearLocalData,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const _SettingsSectionTitle('ACERCA DE'),
        const SizedBox(height: 10),
        _SettingsCard(
          child: Column(
            children: [
              _SettingsTile(
                leading: const _SettingsIcon(
                  icon: Icons.sticky_note_2_outlined,
                  tone: _SettingsIconTone.primary,
                ),
                title: 'NockNock',
                subtitleWidget: FutureBuilder<String>(
                  future: appVersion,
                  builder: (context, snapshot) => Text(
                    'Notas y recordatorios colaborativos · '
                    '${snapshot.data ?? 'Versión…'}',
                    key: const ValueKey('settings-version-label'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              const _SettingsDivider(),
              _SettingsTile(
                key: const ValueKey('settings-privacy-button'),
                leading: const _SettingsIcon(
                  icon: Icons.shield_outlined,
                  tone: _SettingsIconTone.secondary,
                ),
                title: 'Privacidad y seguridad',
                subtitle: 'Cómo protegemos tus notas y datos locales.',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onShowPrivacy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsHero extends StatefulWidget {
  const _SettingsHero({required this.user});

  final AppUser? user;

  @override
  State<_SettingsHero> createState() => _SettingsHeroState();
}

class _SettingsHeroState extends State<_SettingsHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatingController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _floatingController
        ..stop()
        ..value = 0;
    } else if (_floatingController.status == AnimationStatus.dismissed) {
      _floatingController.forward();
    }
  }

  @override
  void dispose() {
    _floatingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TweenAnimationBuilder<double>(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 440),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - value)),
          child: child,
        ),
      ),
      child: Container(
        key: const ValueKey('settings-overview-card'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                colors.primary.withValues(alpha: isDark ? 0.38 : 0.23),
                colors.surface,
              ),
              Color.alphaBlend(
                colors.secondary.withValues(alpha: isDark ? 0.23 : 0.13),
                colors.surface,
              ),
              Color.alphaBlend(
                colors.tertiary.withValues(alpha: isDark ? 0.28 : 0.16),
                colors.surface,
              ),
            ],
            stops: const [0, 0.56, 1],
          ),
          border: Border.all(
            color: colors.primary.withValues(alpha: isDark ? 0.34 : 0.21),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: isDark ? 0.18 : 0.14),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -62,
              top: -78,
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors.tertiary.withValues(alpha: isDark ? 0.22 : 0.16),
                      colors.tertiary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -72,
              bottom: -112,
              child: Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors.primary.withValues(alpha: isDark ? 0.24 : 0.17),
                      colors.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            _SettingsHeroBackgroundIcons(animation: _floatingController),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsHeroLeadingIcon(animation: _floatingController),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tu NockNock, a tu manera',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.55,
                                height: 1.08,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.user == null
                              ? 'Personaliza la app y controla los datos que viven en este dispositivo.'
                              : 'Personaliza la app y revisa cómo se protege tu espacio sincronizado.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.42,
                              ),
                        ),
                        const SizedBox(height: 15),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _HeroPill(
                              icon: widget.user == null
                                  ? Icons.phone_android_rounded
                                  : Icons.cloud_done_outlined,
                              label: widget.user == null
                                  ? 'Local'
                                  : 'Sincronizado',
                            ),
                            const _HeroPill(
                              icon: Icons.lock_outline_rounded,
                              label: 'Privado',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeroLeadingIcon extends StatelessWidget {
  const _SettingsHeroLeadingIcon({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final angle = animation.value * math.pi * 4;
        return Transform.translate(
          key: const ValueKey('settings-hero-leading-icon'),
          offset: Offset(0, math.sin(angle) * 2.2),
          child: Transform.rotate(
            angle: math.sin(angle * 0.5) * 0.025,
            child: child,
          ),
        );
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.primary, colors.tertiary],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.34),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.tune_rounded, color: Colors.white, size: 31),
            Positioned(
              right: 7,
              top: 7,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeroBackgroundIcons extends StatelessWidget {
  const _SettingsHeroBackgroundIcons({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              right: 22,
              top: 18,
              child: _FloatingSettingsIcon(
                id: 'note',
                animation: animation,
                icon: Icons.sticky_note_2_outlined,
                color: colors.primary,
                phase: 0.2,
                cycles: 2,
                amplitude: 7,
                size: 18,
              ),
            ),
            Positioned(
              right: 7,
              top: 92,
              child: _FloatingSettingsIcon(
                id: 'lock',
                animation: animation,
                icon: Icons.lock_outline_rounded,
                color: colors.tertiary,
                phase: 1.4,
                cycles: 3,
                amplitude: 6,
                size: 16,
              ),
            ),
            Positioned(
              right: 76,
              bottom: 14,
              child: _FloatingSettingsIcon(
                id: 'checklist',
                animation: animation,
                icon: Icons.checklist_rounded,
                color: colors.secondary,
                phase: 2.5,
                cycles: 2,
                amplitude: 8,
                size: 20,
              ),
            ),
            Positioned(
              left: 20,
              bottom: 18,
              child: _FloatingSettingsIcon(
                id: 'cloud',
                animation: animation,
                icon: Icons.cloud_done_outlined,
                color: colors.primary,
                phase: 3.7,
                cycles: 3,
                amplitude: 6,
                size: 17,
              ),
            ),
            Positioned(
              left: 112,
              top: 12,
              child: _FloatingSettingsIcon(
                id: 'shield',
                animation: animation,
                icon: Icons.shield_outlined,
                color: colors.tertiary,
                phase: 4.8,
                cycles: 2,
                amplitude: 7,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingSettingsIcon extends StatelessWidget {
  const _FloatingSettingsIcon({
    required this.id,
    required this.animation,
    required this.icon,
    required this.color,
    required this.phase,
    required this.cycles,
    required this.amplitude,
    required this.size,
  });

  final String id;
  final Animation<double> animation;
  final IconData icon;
  final Color color;
  final double phase;
  final int cycles;
  final double amplitude;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final angle = animation.value * math.pi * 2 * cycles + phase;
        return Transform.translate(
          key: ValueKey('settings-floating-icon-$id'),
          offset: Offset(
            math.sin(angle) * amplitude,
            math.cos(angle) * amplitude * 0.62,
          ),
          child: Transform.rotate(
            angle: math.sin(angle + phase) * 0.09,
            child: child,
          ),
        );
      },
      child: Container(
        width: size + 22,
        height: size + 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.075),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, size: size, color: color.withValues(alpha: 0.24)),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.56),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.25,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.055),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 13, sigmaY: 13),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.surface.withValues(alpha: isDark ? 0.82 : 0.88),
                  colors.surfaceContainerLow.withValues(
                    alpha: isDark ? 0.78 : 0.82,
                  ),
                ],
              ),
              border: Border.all(
                color: colors.outlineVariant.withValues(
                  alpha: isDark ? 0.3 : 0.24,
                ),
              ),
            ),
            child: Material(color: Colors.transparent, child: child),
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.titleColor,
    this.onTap,
    this.enabled = true,
    super.key,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final Color? titleColor;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      enabled: enabled,
      minTileHeight: 78,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: leading,
      title: Text(
        title,
        style: TextStyle(
          color: titleColor,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.15,
        ),
      ),
      subtitle:
          subtitleWidget ??
          (subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                )),
      trailing: trailing,
      onTap: enabled ? onTap : null,
    );
  }
}

enum _SettingsIconTone { primary, secondary, tertiary, danger }

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon, required this.tone});

  final IconData icon;
  final _SettingsIconTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (tone) {
      _SettingsIconTone.primary => colors.primary,
      _SettingsIconTone.secondary => colors.secondary,
      _SettingsIconTone.tertiary => colors.tertiary,
      _SettingsIconTone.danger => colors.error,
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, color: color, size: 23),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 76,
      endIndent: 16,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.35),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [colors.primary, colors.tertiary]),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PrivacyDetail extends StatelessWidget {
  const _PrivacyDetail({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: colors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
