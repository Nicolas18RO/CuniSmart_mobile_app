import 'package:flutter/material.dart';

import '../models/rabbit.dart';
import '../voice/engine/voice_ai_engine.dart';
import '../voice/form/rabbit_create_voice_form_guidance.dart';
import '../voice/form/rabbit_create_voice_form_snapshot.dart';
import '../voice/form/voice_form_field.dart';
import '../voice/form/voice_form_field_assignment.dart';

/// Estado del formulario «Crear conejo» enlazado a voz (TextEditingControllers + selects).
class RabbitCreateFormVoiceController extends ChangeNotifier {
  final name = TextEditingController();
  final breed = TextEditingController();
  final birthDate = TextEditingController();
  final weight = TextEditingController();
  final notes = TextEditingController();

  String sex = 'male';
  String status = 'active';

  bool _editMode = false;
  bool _voiceSexExplicit = false;
  bool _weightVoiceAddressed = false;
  bool _statusVoiceExplicit = false;
  bool _notesVoiceExplicit = false;

  bool _armedFinalInLastCompose = false;

  /// El último [composeGuidanceTts] cerró el flujo guiado y pasó a revisión final por voz.
  bool get armedFinalInLastCompose => _armedFinalInLastCompose;

  /// Obligatorios listos para el resumen y confirmación solo por voz (no aplica en modo edición).
  bool get readyForFinalVoiceConfirmation =>
      !_editMode &&
      name.text.trim().isNotEmpty &&
      breed.text.trim().isNotEmpty &&
      _voiceSexExplicit &&
      birthDate.text.trim().isNotEmpty &&
      _weightVoiceAddressed &&
      _statusVoiceExplicit &&
      _notesVoiceExplicit;

  /// Campo que el asistente de voz espera ahora (reintentos STT en el mismo paso).
  VoiceFormField? get activeVoiceField => _computeActiveVoiceField();

  VoiceFormField? _computeActiveVoiceField() {
    if (_editMode) return null;
    if (name.text.trim().isEmpty) return VoiceFormField.name;
    if (breed.text.trim().isEmpty) return VoiceFormField.breed;
    if (!_voiceSexExplicit) return VoiceFormField.sex;
    if (birthDate.text.trim().isEmpty) return VoiceFormField.birthDate;
    if (!_weightVoiceAddressed) return VoiceFormField.weight;
    if (!_statusVoiceExplicit) return VoiceFormField.status;
    if (!_notesVoiceExplicit) return VoiceFormField.notes;
    return null;
  }

  RabbitCreateVoiceFormSnapshot buildSnapshot() {
    return RabbitCreateVoiceFormSnapshot(
      routeOpen: true,
      nameEmpty: name.text.trim().isEmpty,
      breedEmpty: breed.text.trim().isEmpty,
      birthDateEmpty: birthDate.text.trim().isEmpty,
      weightEmpty: weight.text.trim().isEmpty,
      notesEmpty: notes.text.trim().isEmpty,
      activeVoiceField: _computeActiveVoiceField(),
    );
  }

  void importFromRabbit(Rabbit r) {
    _editMode = true;
    name.text = r.name;
    breed.text = r.breed;
    sex = r.sex;
    birthDate.text = r.birthDate;
    weight.text = r.weight?.toString() ?? '';
    status = r.status;
    notes.text = r.notes;
    _voiceSexExplicit = true;
    _weightVoiceAddressed = true;
    _statusVoiceExplicit = true;
    _notesVoiceExplicit = true;
    notifyListeners();
  }

  void setSex(String value) {
    sex = value;
    _voiceSexExplicit = true;
    notifyListeners();
  }

  void setStatus(String value) {
    status = value;
    _statusVoiceExplicit = true;
    notifyListeners();
  }

  void setBirthDateText(String ymd) {
    birthDate.text = ymd;
    notifyListeners();
  }

  void applyAssignments(List<VoiceFormFieldAssignment> items) {
    for (final a in items) {
      switch (a.field) {
        case VoiceFormField.name:
          name.text = a.value;
          break;
        case VoiceFormField.breed:
          breed.text = a.value;
          break;
        case VoiceFormField.sex:
          sex = a.value;
          _voiceSexExplicit = true;
          break;
        case VoiceFormField.birthDate:
          birthDate.text = a.value;
          if (!_voiceSexExplicit) {
            _voiceSexExplicit = true;
          }
          break;
        case VoiceFormField.weight:
          weight.text = a.value;
          _weightVoiceAddressed = true;
          break;
        case VoiceFormField.status:
          status = a.value;
          _statusVoiceExplicit = true;
          break;
        case VoiceFormField.notes:
          notes.text = a.value;
          _notesVoiceExplicit = true;
          if (!_statusVoiceExplicit) {
            status = 'active';
            _statusVoiceExplicit = true;
          }
          break;
      }
    }
    notifyListeners();
  }

  /// Resumen oral antes de confirmar (delegado en [VoiceAIEngine] como texto TTS).
  String buildFinalSummary() {
    final w = weight.text.trim();
    final n = notes.text.trim();
    return VoiceAIEngine.formatRabbitCreateFormFinalSummary(
      name: name.text.trim(),
      breed: breed.text.trim(),
      sexApi: sex,
      birthDateYmd: birthDate.text.trim(),
      statusApi: status,
      weightDisplay: w.isEmpty ? null : w.replaceAll(',', '.'),
      notesPreview: n.isEmpty ? null : n,
    );
  }

  String buildConfirmationPrompt() => VoiceAIEngine.rabbitCreateFormConfirmationPrompt();

  /// Tras [applyAssignments]: confirma lo entendido + siguiente instrucción (un campo por turno),
  /// o resumen + pregunta de confirmación cuando el borrador está completo.
  String composeGuidanceTts(List<VoiceFormFieldAssignment> applied) {
    _armedFinalInLastCompose = false;
    final parts = <String>[];
    for (final a in applied) {
      parts.add(RabbitCreateVoiceFormGuidance.confirmLine(a));
    }
    if (readyForFinalVoiceConfirmation) {
      _armedFinalInLastCompose = true;
      parts.add(buildFinalSummary());
      parts.add(buildConfirmationPrompt());
      return parts.join(' ');
    }
    final next = _nextInstruction();
    if (next.isNotEmpty) {
      parts.add(next);
    }
    return parts.join(' ');
  }

  String _nextInstruction() {
    if (name.text.trim().isEmpty) {
      return 'Di el nombre del conejo.';
    }
    if (breed.text.trim().isEmpty) {
      return 'Ahora dime la raza del conejo.';
    }
    if (!_voiceSexExplicit) {
      return 'Indícame el sexo del conejo: macho o hembra. Macho es el valor por defecto.';
    }
    if (birthDate.text.trim().isEmpty) {
      return '¿Cuál es la fecha de nacimiento del conejo? Puedes decir el día, mes y año.';
    }
    if (!_weightVoiceAddressed) {
      return '¿Cuál es el peso en kilos? O di sin peso.';
    }
    if (!_statusVoiceExplicit) {
      return '¿Cuál es el estado? Activo, vendido o fallecido.';
    }
    if (!_notesVoiceExplicit) {
      return '¿Deseas notas adicionales? Di sin notas si no aplica.';
    }
    return '';
  }

  /// Limpia el formulario tras crear por voz (alta nueva).
  void clearVoiceFormForNewRabbit() {
    name.clear();
    breed.clear();
    birthDate.clear();
    weight.clear();
    notes.clear();
    sex = 'male';
    status = 'active';
    _editMode = false;
    _voiceSexExplicit = false;
    _weightVoiceAddressed = false;
    _statusVoiceExplicit = false;
    _notesVoiceExplicit = false;
    _armedFinalInLastCompose = false;
    notifyListeners();
  }

  @override
  void dispose() {
    name.dispose();
    breed.dispose();
    birthDate.dispose();
    weight.dispose();
    notes.dispose();
    super.dispose();
  }
}
