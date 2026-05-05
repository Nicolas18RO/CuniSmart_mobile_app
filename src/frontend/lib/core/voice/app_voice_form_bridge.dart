import 'package:flutter/foundation.dart';

import '../../viewmodels/rabbit_create_form_voice_controller.dart';
import '../../voice/form/rabbit_create_voice_form_snapshot.dart';
import '../../voice/form/voice_form_field_assignment.dart';

/// Referencia al formulario de creación abierto (registrado por la pantalla).
class AppVoiceFormBridge extends ChangeNotifier {
  RabbitCreateFormVoiceController? _rabbitCreate;

  bool _awaitingFinalConfirmation = false;

  bool get rabbitCreateRouteOpen => _rabbitCreate != null;

  /// Formulario de alta registrado y usable por voz (mismo criterio que [rabbitCreateRouteOpen]).
  bool get isActive => _rabbitCreate != null;

  RabbitCreateFormVoiceController? get rabbitFormController => _rabbitCreate;

  bool get isAwaitingFinalConfirmation => _awaitingFinalConfirmation;

  RabbitCreateVoiceFormSnapshot readRabbitCreateSnapshot() {
    final c = _rabbitCreate;
    if (c == null) {
      return const RabbitCreateVoiceFormSnapshot(
        routeOpen: false,
        nameEmpty: true,
        breedEmpty: true,
        birthDateEmpty: true,
        weightEmpty: true,
        notesEmpty: true,
        activeVoiceField: null,
      );
    }
    return c.buildSnapshot();
  }

  void registerRabbitCreate(RabbitCreateFormVoiceController c) {
    _rabbitCreate = c;
    _awaitingFinalConfirmation = false;
    notifyListeners();
  }

  void unregisterRabbitCreate(RabbitCreateFormVoiceController c) {
    if (_rabbitCreate == c) {
      _rabbitCreate = null;
      _awaitingFinalConfirmation = false;
      notifyListeners();
    }
  }

  void clearAwaitingFinalConfirmation() {
    if (_awaitingFinalConfirmation) {
      _awaitingFinalConfirmation = false;
      notifyListeners();
    }
  }

  void applyRabbitCreateAssignments(List<VoiceFormFieldAssignment> items) {
    _rabbitCreate?.applyAssignments(items);
  }

  /// Aplica campos y devuelve TTS de confirmación + siguiente paso (formulario guiado).
  String? applyRabbitCreateAssignmentsWithGuidance(
    List<VoiceFormFieldAssignment> items,
  ) {
    final c = _rabbitCreate;
    if (c == null) return null;
    c.applyAssignments(items);
    final out = c.composeGuidanceTts(items);
    if (c.armedFinalInLastCompose) {
      _awaitingFinalConfirmation = true;
      notifyListeners();
    }
    return out;
  }

  /// Tras una ráfaga: arma revisión final si el borrador ya está completo.
  String? takeFinalReviewAndArmIfReady() {
    final c = _rabbitCreate;
    if (c == null || _awaitingFinalConfirmation || !c.readyForFinalVoiceConfirmation) {
      return null;
    }
    _awaitingFinalConfirmation = true;
    notifyListeners();
    return '${c.buildFinalSummary()} ${c.buildConfirmationPrompt()}';
  }

  /// Limpia el formulario de alta (tras crear por voz con éxito).
  void clearRabbitCreateFormFields() {
    _rabbitCreate?.clearVoiceFormForNewRabbit();
  }

  /// Reinicia flags de confirmación y el borrador del formulario (sin des-registrar la ruta).
  void hardReset() {
    _awaitingFinalConfirmation = false;
    _rabbitCreate?.clearVoiceFormForNewRabbit();
    notifyListeners();
  }

  /// Libera referencia al controlador y banderas (p. ej. tras cerrar la ruta).
  void clear() {
    _rabbitCreate = null;
    _awaitingFinalConfirmation = false;
    notifyListeners();
  }

  /// Compatibilidad: igual que [clear] solo para flags (si no quieres soltar ref).
  void clearVoiceFormBridge() {
    _awaitingFinalConfirmation = false;
    notifyListeners();
  }
}
