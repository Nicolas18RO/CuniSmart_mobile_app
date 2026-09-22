import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/rabbit.dart';
import '../../models/rabbit_qr.dart';

class RabbitQrView extends StatelessWidget {
  const RabbitQrView({super.key, required this.rabbit});

  final Rabbit rabbit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final payload = RabbitQr.payloadFor(rabbit.uuid);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Código QR',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          children: [
            Semantics(
              label:
                  'Código QR de ${rabbit.name}, identificador ${rabbit.uuid}',
              child: ExcludeSemantics(
                child: ColoredBox(
                  color: Colors.white,
                  child: QrImageView(
                    data: payload,
                    size: 240,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ExcludeSemantics(
              child: Text(
                rabbit.name,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            ExcludeSemantics(
              child: SelectableText(
                rabbit.uuid,
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Este código solo identifica al animal. No incluye nombre, peso ni otros datos.',
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
