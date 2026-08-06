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
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

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
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.system_update_alt_rounded),
        title: const Text('Hay una nueva versión'),
        content: const Text(
          'Actualiza NockNock desde Google Play para obtener las últimas '
          'mejoras y correcciones. Puedes seguir usando la app mientras se '
          'descarga.',
        ),
        actions: [
          TextButton(
            key: const Key('google-play-update-later'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UpdatePromptChoice.later),
            child: const Text('Más tarde'),
          ),
          FilledButton.icon(
            key: const Key('google-play-update-now'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UpdatePromptChoice.update),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Actualizar ahora'),
          ),
        ],
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
