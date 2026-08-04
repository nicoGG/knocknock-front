import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Perfil',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 560),
                child: ProfileCard(),
              ),
            ),
          ],
        ),
      ),
    );
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
  const ProfileCard({super.key});

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
        final colorScheme = Theme.of(context).colorScheme;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: user == null
              ? _SignedOutProfile(
                  isWorking: _isWorking,
                  onSignIn: () => _run(repository.signInWithGoogle),
                )
              : _SignedInProfile(
                  user: user,
                  isWorking: _isWorking,
                  onSignOut: () => _run(repository.signOut),
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
}

class _SignedOutProfile extends StatelessWidget {
  const _SignedOutProfile({required this.isWorking, required this.onSignIn});

  final bool isWorking;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            AuthAvatar(user: null),
            SizedBox(width: 10),
            Text('Tu perfil', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 11),
        Text(
          'Tus cambios se guardan en este dispositivo. Con Google puedes usar '
          'tus notas conectadas.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('google-sign-in-button'),
            onPressed: isWorking ? null : onSignIn,
            icon: isWorking
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const _GoogleMark(),
            label: const Text('Continuar con Google'),
          ),
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
  });

  final AppUser user;
  final bool isWorking;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AuthAvatar(user: user, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cerrar sesión',
          onPressed: isWorking ? null : onSignOut,
          icon: isWorking
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout_rounded, size: 20),
        ),
      ],
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
        color: Color(0xFF4285F4),
        fontSize: 17,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
