part of 'board_page.dart';

/// App chrome and online/offline synchronization status surfaces.

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({
    required this.isConnected,
    required this.isConnecting,
    required this.isEncrypted,
    required this.pendingSyncCount,
    required this.syncConflictCount,
    required this.isSyncingOfflineChanges,
    required this.onSearch,
    required this.onOpenProfile,
    required this.onOpenNotifications,
    required this.scrollProgress,
    this.notificationsController,
  });

  final bool isConnected;
  final bool isConnecting;
  final bool isEncrypted;
  final int pendingSyncCount;
  final int syncConflictCount;
  final bool isSyncingOfflineChanges;
  final VoidCallback onSearch;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;
  final ValueListenable<double> scrollProgress;
  final NotificationsController? notificationsController;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AuthRepository>();
    final colorScheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final useGlassEffects =
        Theme.of(context).platform != TargetPlatform.android;
    return AppBar(
      key: const ValueKey('parallax-app-bar'),
      toolbarHeight: 72,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: Builder(
        builder: (scaffoldContext) => IconButton(
          key: const ValueKey('appbar-menu-button'),
          tooltip: 'Abrir menú',
          onPressed: Scaffold.of(scaffoldContext).openDrawer,
          icon: const Icon(Icons.menu),
        ),
      ),
      flexibleSpace: ValueListenableBuilder<double>(
        valueListenable: scrollProgress,
        builder: (context, rawProgress, _) {
          final progress = Curves.easeOutCubic.transform(
            rawProgress.clamp(0.0, 1.0),
          );
          final backgroundAlpha = 0.03 + (0.63 * progress);
          if (!useGlassEffects) {
            return DecoratedBox(
              key: const ValueKey('appbar-bottom-fade'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.68, 1],
                  colors: [
                    colorScheme.surface.withValues(alpha: backgroundAlpha),
                    colorScheme.surface.withValues(alpha: backgroundAlpha),
                    colorScheme.surface.withValues(alpha: 0),
                  ],
                ),
              ),
              child: const SizedBox.expand(
                key: ValueKey('appbar-parallax-background'),
              ),
            );
          }
          final background = DecoratedBox(
            key: const ValueKey('appbar-parallax-background'),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: backgroundAlpha),
            ),
            child: const SizedBox.expand(),
          );
          return ClipRect(
            child: ShaderMask(
              key: const ValueKey('appbar-bottom-fade'),
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.68, 1],
                colors: [Colors.white, Colors.white, Colors.transparent],
              ).createShader(bounds),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 16 * progress,
                  sigmaY: 16 * progress,
                ),
                child: background,
              ),
            ),
          );
        },
      ),
      actions: [
        Row(
          key: const ValueKey('appbar-actions'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _AnimatedConnectionIndicator(
              isConnected: isConnected,
              isConnecting: isConnecting,
              isEncrypted: isEncrypted,
              pendingSyncCount: pendingSyncCount,
              syncConflictCount: syncConflictCount,
              isSyncingOfflineChanges: isSyncingOfflineChanges,
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('global-note-search-button'),
              tooltip: 'Buscar en todas las listas',
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
            ),
            if (notificationsController case final controller?)
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => NotificationBellButton(
                  key: const ValueKey('notifications-button'),
                  unreadCount: controller.unreadCount,
                  onPressed: onOpenNotifications,
                ),
              ),
            if (notificationsController != null) const SizedBox(width: 2),
            if (!isCompact)
              StreamBuilder<AppUser?>(
                stream: repository.authStateChanges,
                initialData: repository.currentUser,
                builder: (context, snapshot) => Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: IconButton(
                    key: const ValueKey('profile-avatar-button'),
                    tooltip: 'Abrir perfil',
                    padding: const EdgeInsets.all(4),
                    onPressed: onOpenProfile,
                    icon: AuthAvatar(user: snapshot.data),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

void _showConnectionStatusDialog(BuildContext context) {
  final notesCubit = context.read<NotesCubit>();
  final isSignedIn = context.read<AuthRepository>().currentUser != null;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.24),
    builder: (context) => BlocProvider.value(
      value: notesCubit,
      child: _ConnectionStatusDialog(isSignedIn: isSignedIn),
    ),
  );
}

class _OfflineSyncNotice extends StatelessWidget {
  const _OfflineSyncNotice({
    required this.conflictCount,
    required this.isSyncing,
    this.onReviewConflicts,
  });

  final int conflictCount;
  final bool isSyncing;
  final VoidCallback? onReviewConflicts;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final needsReview = conflictCount > 0;
    final color = needsReview ? const Color(0xFFE08A24) : colorScheme.primary;
    final title = needsReview
        ? conflictCount == 1
              ? '1 cambio necesita revisión'
              : '$conflictCount cambios necesitan revisión'
        : isSyncing
        ? 'Sincronizando los cambios guardados'
        : 'Guardado en este dispositivo';
    final detail = needsReview
        ? 'Hay cambios hechos en otro dispositivo que requieren tu decisión.'
        : isSyncing
        ? 'Tus cambios siguen seguros mientras terminamos de enviarlos.'
        : 'Se sincronizará automáticamente al reconectar. No necesitas hacer nada.';

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $detail',
      child: Container(
        key: const ValueKey('offline-sync-notice'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.1,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              needsReview
                  ? Icons.sync_problem_rounded
                  : isSyncing
                  ? Icons.sync_rounded
                  : Icons.cloud_done_outlined,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  if (needsReview && onReviewConflicts != null) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      key: const ValueKey('offline-sync-review-action'),
                      onPressed: onReviewConflicts,
                      icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                      label: const Text('Revisar cambios'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedConnectionIndicator extends StatelessWidget {
  const _AnimatedConnectionIndicator({
    required this.isConnected,
    required this.isConnecting,
    required this.isEncrypted,
    required this.pendingSyncCount,
    required this.syncConflictCount,
    required this.isSyncingOfflineChanges,
  });

  final bool isConnected;
  final bool isConnecting;
  final bool isEncrypted;
  final int pendingSyncCount;
  final int syncConflictCount;
  final bool isSyncingOfflineChanges;

  @override
  Widget build(BuildContext context) {
    final color = syncConflictCount > 0
        ? const Color(0xFFE08A24)
        : isSyncingOfflineChanges || pendingSyncCount > 0
        ? Theme.of(context).colorScheme.primary
        : isConnecting
        ? Theme.of(context).colorScheme.primary
        : isConnected
        ? const Color(0xFF2C9B4A)
        : const Color(0xFFD34242);
    final label = syncConflictCount > 0
        ? '$syncConflictCount cambios necesitan revisión'
        : isSyncingOfflineChanges
        ? 'Sincronizando cambios pendientes'
        : pendingSyncCount > 0
        ? '$pendingSyncCount cambios guardados en el dispositivo'
        : isConnecting
        ? 'Conectando'
        : isConnected
        ? 'Conectado'
        : 'Sin conexión';

    return IconButton(
      key: const ValueKey('connection-status-button'),
      tooltip:
          '$label. Cifrado ${isEncrypted ? 'activo' : 'no activo'}. Ver estado',
      onPressed: () => _showConnectionStatusDialog(context),
      icon: Semantics(
        excludeSemantics: true,
        child: TweenAnimationBuilder<double>(
          key: ValueKey((isConnected, isConnecting)),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            final progress = value.clamp(0.0, 1.0);
            return Transform.scale(
              scale: 0.72 + (progress * 0.28),
              child: Opacity(opacity: 0.45 + (progress * 0.55), child: child),
            );
          },
          child: Container(
            key: ValueKey(
              isConnecting
                  ? 'connecting-status-indicator'
                  : isConnected
                  ? 'connected-status-indicator'
                  : 'disconnected-status-indicator',
            ),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (isConnecting)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      color: color,
                      strokeWidth: 2.2,
                    ),
                  )
                else
                  Icon(
                    isSyncingOfflineChanges || pendingSyncCount > 0
                        ? Icons.cloud_upload_outlined
                        : isConnected
                        ? Icons.wifi_rounded
                        : Icons.wifi_off_rounded,
                    color: color,
                    size: 18,
                  ),
                if (syncConflictCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(syncConflictCount),
                      tween: Tween(begin: 0.6, end: 1),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      curve: Curves.easeOutBack,
                      builder: (context, value, child) =>
                          Transform.scale(scale: value, child: child),
                      child: Container(
                        key: const ValueKey('connection-conflict-badge'),
                        constraints: const BoxConstraints(
                          minWidth: 17,
                          minHeight: 17,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE08A24),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFE08A24,
                              ).withValues(alpha: 0.28),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          syncConflictCount > 99 ? '99+' : '$syncConflictCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: _AnimatedEncryptionBadge(isEncrypted: isEncrypted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedEncryptionBadge extends StatelessWidget {
  const _AnimatedEncryptionBadge({required this.isEncrypted});

  final bool isEncrypted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isEncrypted
        ? const Color(0xFF2C9B4A)
        : const Color(0xFFE08A24);
    return TweenAnimationBuilder<double>(
      key: ValueKey(isEncrypted),
      tween: Tween(begin: 0.55, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, value, child) => Transform.rotate(
        angle: (1 - value) * -0.28,
        child: Transform.scale(scale: value, child: child),
      ),
      child: Container(
        key: const ValueKey('encryption-lock-badge'),
        width: 17,
        height: 17,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.surface, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.32),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isEncrypted ? Icons.lock_rounded : Icons.lock_open_rounded,
          color: Colors.white,
          size: 9,
        ),
      ),
    );
  }
}

class _ConnectionStatusDialog extends StatelessWidget {
  const _ConnectionStatusDialog({required this.isSignedIn});

  final bool isSignedIn;

  @override
  Widget build(BuildContext context) => BlocBuilder<NotesCubit, NotesState>(
    builder: (context, state) => _buildDialog(context, state),
  );

  Widget _buildDialog(BuildContext context, NotesState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final isConnected = state.isRealtimeConnected;
    final isConnecting = state.isRealtimeConnecting;
    final notesStatus = state.status;
    final selectedList = state.selectedList;
    final noteCount = state.notes.length;
    final isSyncing =
        state.isSaving ||
        state.isSavingList ||
        state.isInviting ||
        state.isRemovingCollaborator ||
        state.isSavingAppearance ||
        state.isLoadingPinned ||
        state.isLoadingReminderNotes ||
        state.isSyncingOfflineChanges;
    final backendColor = isConnecting
        ? colorScheme.primary
        : isConnected
        ? const Color(0xFF2C9B4A)
        : colorScheme.error;
    final encryptionVersion = selectedList?.encryption.version;
    final isEncrypted = encryptionVersion != null && encryptionVersion > 0;
    final selectedListName = selectedList?.name ?? 'Cargando lista';
    final loadedNotesLabel = noteCount == 1
        ? '1 nota cargada'
        : '$noteCount notas cargadas';

    final String syncStatus;
    final String syncDetail;
    final IconData syncIcon;
    final Color syncColor;
    if (!isSignedIn) {
      syncStatus = 'Solo en este dispositivo';
      syncDetail =
          'Inicia sesión para sincronizar tus listas y notas entre dispositivos.';
      syncIcon = Icons.phone_android_rounded;
      syncColor = colorScheme.primary;
    } else if (state.syncConflictCount > 0) {
      syncStatus = 'Necesita revisión';
      syncDetail = state.syncConflictCount == 1
          ? 'Hay un cambio local que coincide con una edición realizada en otro dispositivo.'
          : 'Hay ${state.syncConflictCount} cambios locales que coinciden con ediciones realizadas en otros dispositivos.';
      syncIcon = Icons.sync_problem_rounded;
      syncColor = const Color(0xFFE08A24);
    } else if (state.pendingSyncCount > 0 || state.isSyncingOfflineChanges) {
      syncStatus = state.isSyncingOfflineChanges
          ? 'Sincronizando cambios'
          : 'Guardado en este dispositivo';
      syncDetail = state.isSyncingOfflineChanges
          ? 'Estamos enviando de forma segura los cambios que hiciste sin conexión.'
          : 'Tus cambios están seguros y se enviarán cuando vuelva la conexión.';
      syncIcon = state.isSyncingOfflineChanges
          ? Icons.sync_rounded
          : Icons.cloud_upload_outlined;
      syncColor = colorScheme.primary;
    } else if (isConnecting) {
      syncStatus = 'Esperando conexión';
      syncDetail =
          'La lista permanece disponible mientras restablecemos el canal en tiempo real.';
      syncIcon = Icons.cloud_sync_outlined;
      syncColor = colorScheme.primary;
    } else if (isSyncing || notesStatus == NotesStatus.loading) {
      syncStatus = 'Sincronizando';
      syncDetail = 'Estamos actualizando la información de tu cuenta.';
      syncIcon = Icons.sync_rounded;
      syncColor = colorScheme.primary;
    } else if (isConnected && notesStatus == NotesStatus.ready) {
      syncStatus = 'Al día';
      syncDetail = 'La lista y sus notas están actualizadas.';
      syncIcon = Icons.cloud_done_outlined;
      syncColor = const Color(0xFF2C9B4A);
    } else {
      syncStatus = 'En pausa';
      syncDetail =
          'Mostramos la última copia guardada hasta recuperar la conexión.';
      syncIcon = Icons.cloud_off_outlined;
      syncColor = const Color(0xFFE08A24);
    }

    final String encryptionStatus;
    final String encryptionDetail;
    final IconData encryptionIcon;
    final Color encryptionColor;
    if (!isSignedIn) {
      encryptionStatus = 'Disponible al iniciar sesión';
      encryptionDetail =
          'En modo invitado, el contenido permanece guardado localmente en este dispositivo.';
      encryptionIcon = Icons.phonelink_lock_outlined;
      encryptionColor = colorScheme.primary;
    } else if (selectedList == null) {
      encryptionStatus = 'Verificando';
      encryptionDetail =
          'El estado de protección aparecerá cuando termine de cargar la lista.';
      encryptionIcon = Icons.shield_outlined;
      encryptionColor = colorScheme.primary;
    } else if (isEncrypted) {
      encryptionStatus = 'Activo en esta lista';
      encryptionDetail =
          'La lista y el contenido de sus notas se cifran en este dispositivo antes de sincronizarse.';
      encryptionIcon = Icons.enhanced_encryption_outlined;
      encryptionColor = const Color(0xFF2C9B4A);
    } else {
      encryptionStatus = 'Protección pendiente';
      encryptionDetail =
          'Esta lista todavía no informa cifrado de extremo a extremo activo.';
      encryptionIcon = Icons.gpp_maybe_outlined;
      encryptionColor = const Color(0xFFE08A24);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogMaxHeight = MediaQuery.sizeOf(context).height - 48;
    final glassBorder = Colors.white.withValues(alpha: isDark ? 0.14 : 0.48);

    return Dialog(
      key: const ValueKey('connection-status-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            key: const ValueKey('connection-status-glass-surface'),
            width: 560,
            constraints: BoxConstraints(maxHeight: dialogMaxHeight),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        colorScheme.surface.withValues(alpha: 0.8),
                        colorScheme.surfaceContainerHigh.withValues(
                          alpha: 0.66,
                        ),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.74),
                        colorScheme.surface.withValues(alpha: 0.6),
                      ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: glassBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.2),
                  blurRadius: 36,
                  spreadRadius: -8,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.34),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 18, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              backendColor.withValues(alpha: 0.26),
                              backendColor.withValues(alpha: 0.1),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: backendColor.withValues(alpha: 0.28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: backendColor.withValues(alpha: 0.16),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: isConnecting
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  color: backendColor,
                                  strokeWidth: 2.4,
                                ),
                              )
                            : Icon(
                                isConnected
                                    ? Icons.wifi_rounded
                                    : Icons.wifi_off_rounded,
                                color: backendColor,
                                size: 24,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estado de NockNock',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.35,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Actualizado en tiempo real',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('close-connection-status-dialog'),
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(
                            alpha: isDark ? 0.07 : 0.42,
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: isDark ? 0.09 : 0.42),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: Column(
                      children: [
                        _ConnectionStatusRow(
                          key: const ValueKey('backend-status-row'),
                          icon: isConnecting
                              ? Icons.sync_rounded
                              : isConnected
                              ? Icons.dns_rounded
                              : Icons.cloud_off_outlined,
                          label: 'Backend',
                          status: isConnecting
                              ? 'Conectando…'
                              : isConnected
                              ? 'Conectado'
                              : 'Sin conexión',
                          detail: isConnecting
                              ? 'Estamos autenticando el dispositivo y abriendo el canal para recibir cambios.'
                              : isConnected
                              ? 'La app mantiene un canal abierto para recibir cambios sin tener que actualizar manualmente.'
                              : 'No hay un canal activo. Los cambios de otras personas no llegarán hasta recuperar la conexión.',
                          facts: [
                            (
                              'Canal en tiempo real',
                              isConnecting
                                  ? 'Estableciendo…'
                                  : isConnected
                                  ? 'Activo'
                                  : 'Inactivo',
                            ),
                            (
                              'Cambios colaborativos',
                              isConnecting
                                  ? 'Esperando conexión'
                                  : isConnected
                                  ? 'Automáticos'
                                  : 'En pausa',
                            ),
                          ],
                          factsKey: const ValueKey('backend-status-details'),
                          showProgress: isConnecting,
                          color: backendColor,
                        ),
                        const SizedBox(height: 12),
                        _ConnectionStatusRow(
                          key: const ValueKey('sync-status-row'),
                          icon: syncIcon,
                          label: 'Sincronización',
                          status: syncStatus,
                          detail: syncDetail,
                          facts: [
                            (
                              'Cuenta',
                              isSignedIn ? 'Conectada' : 'Modo invitado',
                            ),
                            ('Lista actual', selectedListName),
                            ('Contenido disponible', loadedNotesLabel),
                            ('Cambios pendientes', '${state.pendingSyncCount}'),
                            ('Conflictos', '${state.syncConflictCount}'),
                            (
                              'Operación en curso',
                              isSyncing || notesStatus == NotesStatus.loading
                                  ? 'Sí'
                                  : 'No',
                            ),
                          ],
                          factsKey: const ValueKey('sync-status-details'),
                          color: syncColor,
                        ),
                        if (state.syncConflictCount > 0) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              key: const ValueKey('review-sync-conflicts'),
                              onPressed: () => showSyncConflictsSheet(
                                context: context,
                                cubit: context.read<NotesCubit>(),
                              ),
                              icon: const Icon(Icons.compare_arrows_rounded),
                              label: const Text('Revisar cambios'),
                            ),
                          ),
                        ] else if (state.pendingSyncCount > 0 &&
                            !state.isSyncingOfflineChanges) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const ValueKey('retry-offline-sync'),
                              onPressed: context
                                  .read<NotesCubit>()
                                  .retryOfflineSync,
                              icon: const Icon(Icons.sync_rounded),
                              label: const Text('Intentar sincronizar'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _ConnectionStatusRow(
                          key: const ValueKey('encryption-status-row'),
                          icon: encryptionIcon,
                          label: 'Cifrado de lista y notas',
                          status: encryptionStatus,
                          detail: encryptionDetail,
                          facts: !isSignedIn
                              ? const [
                                  ('Ubicación', 'Solo este dispositivo'),
                                  (
                                    'Cifrado al sincronizar',
                                    'Requiere iniciar sesión',
                                  ),
                                ]
                              : isEncrypted
                              ? const [
                                  ('Contenido', 'AES-256-GCM'),
                                  (
                                    'Claves de la lista',
                                    'Protegidas por dispositivo',
                                  ),
                                  ('Acceso', 'Personas autorizadas'),
                                ]
                              : [
                                  (
                                    'Versión de cifrado',
                                    '${encryptionVersion ?? 0}',
                                  ),
                                  ('Estado de las claves', 'Pendiente'),
                                ],
                          factsKey: const ValueKey('encryption-status-details'),
                          color: encryptionColor,
                        ),
                      ],
                    ),
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

class _ConnectionStatusRow extends StatelessWidget {
  const _ConnectionStatusRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.detail,
    this.facts = const [],
    this.factsKey,
    this.showProgress = false,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final String status;
  final String detail;
  final List<(String, String)> facts;
  final Key? factsKey;
  final bool showProgress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.075),
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                ]
              : [
                  Colors.white.withValues(alpha: 0.58),
                  colorScheme.surface.withValues(alpha: 0.32),
                ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.11 : 0.52),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.07),
            blurRadius: 18,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: showProgress
                    ? Padding(
                        padding: const EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          color: color,
                          strokeWidth: 2.2,
                        ),
                      )
                    : Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        status,
                        key: ValueKey(status),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: factsKey,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(
                  alpha: isDark ? 0.46 : 0.38,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.07 : 0.36),
                ),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < facts.length; index++) ...[
                    _ConnectionStatusFact(
                      label: facts[index].$1,
                      value: facts[index].$2,
                    ),
                    if (index != facts.length - 1)
                      Divider(
                        height: 15,
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.45,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionStatusFact extends StatelessWidget {
  const _ConnectionStatusFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
