import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const googlePlayUpdateSnoozedAtKey = 'google_play_update_snoozed_at';
const googlePlayUpdateSnoozeDuration = Duration(hours: 24);

enum PlayUpdateInstallStatus { other, downloaded, failed, canceled }

enum PlayUpdateStartResult { accepted, denied, failed }

class PlayUpdateCheck {
  const PlayUpdateCheck({
    required this.updateAvailable,
    required this.flexibleUpdateAllowed,
    required this.downloaded,
    this.availableVersionCode,
  });

  final bool updateAvailable;
  final bool flexibleUpdateAllowed;
  final bool downloaded;
  final int? availableVersionCode;
}

abstract interface class PlayUpdateGateway {
  Stream<PlayUpdateInstallStatus> get installStatuses;

  Future<PlayUpdateCheck> checkForUpdate();

  Future<PlayUpdateStartResult> startFlexibleUpdate();

  Future<void> completeFlexibleUpdate();

  Future<void> openStoreListing();
}

class GooglePlayUpdateGateway implements PlayUpdateGateway {
  const GooglePlayUpdateGateway();

  static final Uri _marketUri = Uri.parse(
    'market://details?id=cl.nocknock.app',
  );
  static final Uri _webUri = Uri.parse(
    'https://play.google.com/store/apps/details?id=cl.nocknock.app',
  );

  @override
  Stream<PlayUpdateInstallStatus> get installStatuses =>
      InAppUpdate.installUpdateListener.map((status) {
        return switch (status) {
          InstallStatus.downloaded => PlayUpdateInstallStatus.downloaded,
          InstallStatus.failed => PlayUpdateInstallStatus.failed,
          InstallStatus.canceled => PlayUpdateInstallStatus.canceled,
          _ => PlayUpdateInstallStatus.other,
        };
      });

  @override
  Future<PlayUpdateCheck> checkForUpdate() async {
    final info = await InAppUpdate.checkForUpdate();
    return PlayUpdateCheck(
      updateAvailable:
          info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress,
      flexibleUpdateAllowed: info.flexibleUpdateAllowed,
      downloaded: info.installStatus == InstallStatus.downloaded,
      availableVersionCode: info.availableVersionCode,
    );
  }

  @override
  Future<PlayUpdateStartResult> startFlexibleUpdate() async {
    final result = await InAppUpdate.startFlexibleUpdate();
    return switch (result) {
      AppUpdateResult.success => PlayUpdateStartResult.accepted,
      AppUpdateResult.userDeniedUpdate => PlayUpdateStartResult.denied,
      AppUpdateResult.inAppUpdateFailed => PlayUpdateStartResult.failed,
    };
  }

  @override
  Future<void> completeFlexibleUpdate() => InAppUpdate.completeFlexibleUpdate();

  @override
  Future<void> openStoreListing() async {
    if (await canLaunchUrl(_marketUri)) {
      await launchUrl(_marketUri, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(_webUri, mode: LaunchMode.externalApplication);
  }
}

class GooglePlayUpdatePrompt extends StatefulWidget {
  const GooglePlayUpdatePrompt({
    required this.child,
    required this.preferences,
    required this.navigatorKey,
    this.gateway = const GooglePlayUpdateGateway(),
    this.enabled,
    this.now = DateTime.now,
    super.key,
  });

  final Widget child;
  final SharedPreferences preferences;
  final GlobalKey<NavigatorState> navigatorKey;
  final PlayUpdateGateway gateway;
  final bool? enabled;
  final DateTime Function() now;

  @override
  State<GooglePlayUpdatePrompt> createState() => _GooglePlayUpdatePromptState();
}

class _GooglePlayUpdatePromptState extends State<GooglePlayUpdatePrompt> {
  StreamSubscription<PlayUpdateInstallStatus>? _installSubscription;
  bool _checked = false;
  bool _showingReadyMessage = false;
  bool _completingUpdate = false;

  bool get _isEnabled =>
      widget.enabled ??
      (!kDebugMode &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    if (!_isEnabled) return;

    _installSubscription = widget.gateway.installStatuses.listen(
      _handleInstallStatus,
      onError: (_) => _showUpdateFailure(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdate());
    });
  }

  Future<void> _checkForUpdate() async {
    if (_checked || !mounted) return;
    _checked = true;

    final snoozedAt = widget.preferences.getInt(googlePlayUpdateSnoozedAtKey);
    if (snoozedAt != null) {
      final elapsed = widget.now().difference(
        DateTime.fromMillisecondsSinceEpoch(snoozedAt),
      );
      if (!elapsed.isNegative && elapsed < googlePlayUpdateSnoozeDuration) {
        return;
      }
    }

    try {
      final update = await widget.gateway.checkForUpdate();
      if (!mounted || !update.updateAvailable) return;
      if (update.downloaded) {
        _showReadyToInstall();
        return;
      }
      await _showUpdatePrompt(
        flexibleUpdateAllowed: update.flexibleUpdateAllowed,
      );
    } catch (error, stackTrace) {
      debugPrint('Google Play update check failed: $error\n$stackTrace');
    }
  }

  Future<void> _showUpdatePrompt({required bool flexibleUpdateAllowed}) async {
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    final choice = await showDialog<_UpdatePromptChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _PlayUpdateDialog(
        flexibleUpdateAllowed: flexibleUpdateAllowed,
        onLater: () =>
            Navigator.of(dialogContext).pop(_UpdatePromptChoice.later),
        onUpdate: () =>
            Navigator.of(dialogContext).pop(_UpdatePromptChoice.update),
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == _UpdatePromptChoice.later) {
      await _snoozePrompt();
      return;
    }
    if (flexibleUpdateAllowed) {
      await _startFlexibleUpdate();
      return;
    }
    await _openStoreListing();
  }

  Future<void> _startFlexibleUpdate() async {
    try {
      final result = await widget.gateway.startFlexibleUpdate();
      if (!mounted) return;
      switch (result) {
        case PlayUpdateStartResult.accepted:
          _showMessage(
            'La actualización se está descargando desde Google Play.',
          );
        case PlayUpdateStartResult.denied:
          await _snoozePrompt();
        case PlayUpdateStartResult.failed:
          _showUpdateFailure();
      }
    } catch (error, stackTrace) {
      debugPrint('Google Play update start failed: $error\n$stackTrace');
      _showUpdateFailure();
    }
  }

  void _handleInstallStatus(PlayUpdateInstallStatus status) {
    switch (status) {
      case PlayUpdateInstallStatus.downloaded:
        _showReadyToInstall();
      case PlayUpdateInstallStatus.failed:
        _showUpdateFailure();
      case PlayUpdateInstallStatus.canceled:
      case PlayUpdateInstallStatus.other:
        break;
    }
  }

  void _showReadyToInstall() {
    if (_showingReadyMessage) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    _showingReadyMessage = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
        ?.showSnackBar(
          SnackBar(
            duration: const Duration(days: 1),
            content: const Text('La actualización está lista para instalar.'),
            action: SnackBarAction(
              key: const Key('google-play-update-restart'),
              label: 'Reiniciar',
              onPressed: () => unawaited(_completeUpdate()),
            ),
          ),
        )
        .closed
        .then((_) => _showingReadyMessage = false);
  }

  Future<void> _completeUpdate() async {
    if (_completingUpdate) return;
    _completingUpdate = true;
    try {
      await widget.gateway.completeFlexibleUpdate();
    } catch (error, stackTrace) {
      debugPrint('Google Play update completion failed: $error\n$stackTrace');
      _showUpdateFailure();
    } finally {
      _completingUpdate = false;
    }
  }

  Future<void> _snoozePrompt() => widget.preferences.setInt(
    googlePlayUpdateSnoozedAtKey,
    widget.now().millisecondsSinceEpoch,
  );

  Future<void> _openStoreListing() async {
    try {
      await widget.gateway.openStoreListing();
    } catch (error, stackTrace) {
      debugPrint('Google Play Store launch failed: $error\n$stackTrace');
      _showUpdateFailure();
    }
  }

  void _showUpdateFailure() {
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: const Text(
          'No pudimos iniciar la actualización automáticamente.',
        ),
        action: SnackBarAction(
          label: 'Abrir Play Store',
          onPressed: () => unawaited(_openStoreListing()),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    unawaited(_installSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _UpdatePromptChoice { later, update }

class _PlayUpdateDialog extends StatelessWidget {
  const _PlayUpdateDialog({
    required this.flexibleUpdateAllowed,
    required this.onLater,
    required this.onUpdate,
  });

  final bool flexibleUpdateAllowed;
  final VoidCallback onLater;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    return Dialog(
      key: const Key('google-play-update-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      backgroundColor: colors.surface,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.primaryContainer,
                          colors.secondaryContainer,
                        ],
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.rotate(
                          angle: -.12,
                          child: Icon(
                            Icons.sticky_note_2_rounded,
                            size: 48,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            size: 22,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      'NockNock · Nueva versión',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Hay una nueva versión',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Tus notas, cada vez mejor. Actualiza para disfrutar de las últimas mejoras y correcciones.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        flexibleUpdateAllowed
                            ? Icons.downloading_rounded
                            : Icons.shop_rounded,
                        size: 22,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          flexibleUpdateAllowed
                              ? 'Puedes seguir usando la app mientras se descarga.'
                              : 'Te llevaremos a Google Play para actualizar la app.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('google-play-update-now'),
                  onPressed: onUpdate,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    shape: rounded,
                    textStyle: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 22),
                  label: const Text('Actualizar ahora'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  key: const Key('google-play-update-later'),
                  onPressed: onLater,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    foregroundColor: colors.onSurfaceVariant,
                    side: BorderSide(color: colors.outlineVariant),
                    shape: rounded,
                  ),
                  child: const Text('Más tarde'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
