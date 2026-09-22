import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/state/submit_state.dart';
import '../../models/rabbit.dart';
import '../../viewmodels/rabbit_viewmodel.dart';

class RabbitQrScanView extends StatefulWidget {
  const RabbitQrScanView({super.key});

  @override
  State<RabbitQrScanView> createState() => _RabbitQrScanViewState();
}

class _RabbitQrScanViewState extends State<RabbitQrScanView> {
  final MobileScannerController _controller = MobileScannerController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .firstOrNull;
    if (raw == null) return;
    await _lookup(raw);
  }

  Future<void> _lookup(String raw) async {
    if (_busy) return;
    final vm = context.read<RabbitViewModel>();
    setState(() => _busy = true);
    await _controller.stop();
    if (!mounted) return;
    final Rabbit? rabbit = await vm.lookupFromQr(raw);
    if (!mounted) return;
    if (rabbit != null) {
      Navigator.of(context).pop(rabbit);
      return;
    }
    await _controller.start();
    if (!mounted) return;
    setState(() => _busy = false);
    final msg = switch (vm.submitState) {
      SubmitFailed(:final message) => message,
      _ => 'No se pudo leer el código',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Escanear QR',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Semantics(
              label: 'Apunta la cámara al código QR del conejo',
              image: true,
              child: ExcludeSemantics(
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Text(
                'Apunta la cámara al código QR del conejo.',
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
