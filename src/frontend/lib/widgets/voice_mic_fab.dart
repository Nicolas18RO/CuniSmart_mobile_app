import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/voice_viewmodel.dart';

/// FAB de micrófono (solo presentación + toggle existente).
///
/// No altera [VoiceViewModel]; solo llama [VoiceViewModel.toggleMicrophone].
class VoiceMicFab extends StatefulWidget {
  const VoiceMicFab({
    super.key,
    required this.heroTag,
    this.debugBypassStt = false,
  });

  final Object heroTag;

  /// Solo tests/debug: mismo bypass que el shell histórico.
  final bool debugBypassStt;

  @override
  State<VoiceMicFab> createState() => _VoiceMicFabState();
}

class _VoiceMicFabState extends State<VoiceMicFab> {
  Future<void> _toggle() async {
    final vm = context.read<VoiceViewModel>();
    debugPrint(
      'VoiceMic: tap isListening=${vm.voice.isListening} '
      'debugBypassStt=${widget.debugBypassStt}',
    );

    if (kDebugMode && widget.debugBypassStt) {
      debugPrint(
          'VoiceMic: debug bypass — applyCommandFromText("ver conejos")');
      await vm.applyCommandFromText('ver conejos');
      if (mounted) setState(() {});
      return;
    }

    await vm.toggleMicrophone();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VoiceViewModel>();
    final listening = vm.isVoiceModeEnabled;
    final scheme = Theme.of(context).colorScheme;
    final semanticsLabel =
        listening ? 'Detener interacción por voz' : 'Interacción por voz';

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: FloatingActionButton.small(
        heroTag: widget.heroTag,
        tooltip: semanticsLabel,
        backgroundColor: listening
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        foregroundColor:
            listening ? scheme.onTertiaryContainer : scheme.onSurface,
        elevation: 3,
        onPressed: _toggle,
        child: const Icon(Icons.mic),
      ),
    );
  }
}
