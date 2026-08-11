import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/presentation/list_biometric_copy.dart';

class ListProtectionPrivacyGuard extends StatefulWidget {
  const ListProtectionPrivacyGuard({
    required this.controller,
    required this.child,
    super.key,
  });

  final ListProtectionController controller;
  final Widget child;

  @override
  State<ListProtectionPrivacyGuard> createState() =>
      _ListProtectionPrivacyGuardState();
}

class _ListProtectionPrivacyGuardState extends State<ListProtectionPrivacyGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.controller.lockAll(protectEntireApp: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (widget.controller.privacyShieldRequired &&
              widget.controller.isActiveListLocked)
            Positioned.fill(
              child: ListProtectionLockedView(controller: widget.controller),
            ),
        ],
      ),
    );
  }
}

class ListProtectionLockedView extends StatelessWidget {
  const ListProtectionLockedView({required this.controller, super.key});

  final ListProtectionController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final platform = Theme.of(context).platform;
    final errorMessage = switch (controller.lastResult) {
      ListProtectionResult.unavailable =>
        '${listBiometricSetupInstruction(platform)} en este dispositivo para continuar.',
      ListProtectionResult.failed =>
        'No pudimos comprobar tu identidad. Inténtalo nuevamente.',
      _ => null,
    };
    return PopScope(
      canPop: false,
      child: Material(
        key: const ValueKey('protected-list-gate'),
        color: colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.13),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_person_rounded,
                        size: 46,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Lista protegida',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      listBiometricUnlockInstruction(platform),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        errorMessage,
                        key: const ValueKey('protected-list-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      key: const ValueKey('unlock-protected-list-button'),
                      onPressed: controller.isAuthenticating
                          ? null
                          : controller.unlockActiveList,
                      icon: controller.isAuthenticating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(listBiometricIcon(platform)),
                      label: Text(
                        controller.isAuthenticating
                            ? 'Comprobando…'
                            : 'Desbloquear',
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
}
