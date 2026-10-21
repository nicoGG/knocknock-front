import 'dart:async';

import 'package:flutter/material.dart';

class CompletionUndoCountdown extends StatefulWidget {
  const CompletionUndoCountdown({
    required this.seconds,
    required this.onExpired,
    super.key,
  });

  final int seconds;
  final VoidCallback onExpired;

  @override
  State<CompletionUndoCountdown> createState() =>
      _CompletionUndoCountdownState();
}

class _CompletionUndoCountdownState extends State<CompletionUndoCountdown> {
  Timer? _timer;
  late int _remaining = widget.seconds;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = widget.seconds - timer.tick;
      if (remaining <= 0) {
        _timer?.cancel();
        widget.onExpired();
      } else {
        setState(() => _remaining = remaining);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Text('Tarea completada')),
      const SizedBox(width: 12),
      Semantics(
        label: 'Quedan $_remaining segundos para deshacer',
        excludeSemantics: true,
        child: Text(
          '$_remaining s',
          key: const ValueKey('completion-undo-countdown'),
        ),
      ),
    ],
  );
}
