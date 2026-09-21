import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/rabbit.dart';
import '../../viewmodels/rabbit_create_form_voice_controller.dart';
import 'rabbit_create_view.dart';

/// Ruta con [RabbitCreateFormVoiceController] para vincular STT al formulario.
class RabbitCreateRoute extends StatelessWidget {
  const RabbitCreateRoute({super.key, this.rabbit});

  final Rabbit? rabbit;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RabbitCreateFormVoiceController(),
      child: RabbitCreateView(rabbit: rabbit),
    );
  }
}
