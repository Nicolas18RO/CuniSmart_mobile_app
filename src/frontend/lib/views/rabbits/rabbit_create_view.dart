import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/submit_state.dart';
import '../../models/rabbit.dart';
import '../../viewmodels/rabbit_viewmodel.dart';

/// Formats [d] as `YYYY-MM-DD` for the API (same file helper).
String _formatRabbitBirthDateYmd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime? _parseRabbitBirthDateYmd(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  try {
    return DateTime.parse(t);
  } catch (_) {
    return null;
  }
}

class RabbitCreateView extends StatefulWidget {
  const RabbitCreateView({super.key, this.rabbit});

  /// When set, form opens in edit mode (PUT update).
  final Rabbit? rabbit;

  @override
  State<RabbitCreateView> createState() => _RabbitCreateViewState();
}

class _RabbitCreateViewState extends State<RabbitCreateView> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _breed = TextEditingController();
  final _birthDate = TextEditingController();
  final _weight = TextEditingController();
  final _notes = TextEditingController();

  String _sex = 'male';
  String _status = 'active';

  static const double _fieldGap = 20;
  static const EdgeInsets _fieldPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 18);

  InputDecoration _decoration(
    BuildContext context,
    String label, {
    String? hint,
    bool calendarSuffix = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline.withOpacity(0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      contentPadding: _fieldPadding,
      labelStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      hintStyle: TextStyle(
        fontSize: 16,
        color: scheme.onSurface.withOpacity(0.55),
      ),
      suffixIcon: calendarSuffix
          ? const Icon(Icons.calendar_today_outlined)
          : null,
    );
  }

  TextStyle _fieldTextStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 18,
      height: 1.35,
      color: scheme.onSurface,
      fontWeight: FontWeight.w500,
    );
  }

  @override
  void initState() {
    super.initState();
    final r = widget.rabbit;
    if (r != null) {
      _name.text = r.name;
      _breed.text = r.breed;
      _sex = r.sex;
      _birthDate.text = r.birthDate;
      if (r.weight != null) {
        _weight.text = r.weight.toString();
      }
      _status = r.status;
      _notes.text = r.notes;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _birthDate.dispose();
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate(BuildContext context) async {
    if (!mounted) return;
    final now = DateTime.now();
    final parsed = _parseRabbitBirthDateYmd(_birthDate.text);
    var initial = parsed ?? DateTime(now.year - 1, now.month, now.day);
    if (initial.isAfter(now)) initial = now;
    final first = DateTime(1900);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: now,
      helpText: 'Fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate.text = _formatRabbitBirthDateYmd(picked);
      });
    }
  }

  Future<void> _submit(RabbitViewModel vm) async {
    if (!_formKey.currentState!.validate()) return;

    final weightText = _weight.text.trim();
    double? weight;
    if (weightText.isNotEmpty) {
      weight = double.tryParse(weightText);
      if (weight == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El peso debe ser un número')),
        );
        return;
      }
    }

    vm.clearSubmitError();

    final editing = widget.rabbit;
    final ok = editing == null
        ? await vm.createRabbit(
            name: _name.text.trim(),
            breed: _breed.text.trim(),
            sex: _sex,
            birthDate: _birthDate.text.trim(),
            weight: weight,
            status: _status,
            notes: _notes.text.trim(),
          )
        : await vm.updateRabbit(
            id: editing.id,
            name: _name.text.trim(),
            breed: _breed.text.trim(),
            sex: _sex,
            birthDate: _birthDate.text.trim(),
            weight: weight,
            status: _status,
            notes: _notes.text.trim(),
          );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RabbitViewModel>();
    final submitting = vm.isSubmitting;
    final submitError = switch (vm.submitState) {
      SubmitFailed(:final message) => message,
      _ => null,
    };

    final isEdit = widget.rabbit != null;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit ? 'Editar conejo' : 'Crear conejo',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              isEdit
                  ? 'Actualice los datos abajo.'
                  : 'Complete cada campo. * significa obligatorio.',
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withOpacity(0.85),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              enabled: !submitting,
              style: _fieldTextStyle(context),
              decoration: _decoration(context, 'Nombre *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Escriba el nombre' : null,
            ),
            const SizedBox(height: _fieldGap),
            TextFormField(
              controller: _breed,
              enabled: !submitting,
              style: _fieldTextStyle(context),
              decoration: _decoration(context, 'Raza *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Escriba la raza' : null,
            ),
            const SizedBox(height: _fieldGap),
            DropdownButtonFormField<String>(
              value: _sex,
              decoration: _decoration(context, 'Sexo *'),
              style: _fieldTextStyle(context),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Macho')),
                DropdownMenuItem(value: 'female', child: Text('Hembra')),
              ],
              onChanged: submitting
                  ? null
                  : (v) => setState(() => _sex = v ?? 'male'),
            ),
            const SizedBox(height: _fieldGap),
            TextFormField(
              controller: _birthDate,
              readOnly: true,
              enabled: !submitting,
              style: _fieldTextStyle(context),
              decoration: _decoration(
                context,
                'Fecha de nacimiento *',
                hint: 'Toca para elegir',
                calendarSuffix: true,
              ),
              onTap: submitting ? null : () => _pickBirthDate(context),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Elija la fecha de nacimiento' : null,
            ),
            const SizedBox(height: _fieldGap),
            TextFormField(
              controller: _weight,
              enabled: !submitting,
              style: _fieldTextStyle(context),
              decoration: _decoration(
                context,
                'Peso (kg)',
                hint: 'Opcional — deje vacío si no sabe',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: _fieldGap),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: _decoration(context, 'Estado *'),
              style: _fieldTextStyle(context),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Activo')),
                DropdownMenuItem(value: 'sold', child: Text('Vendido')),
                DropdownMenuItem(value: 'deceased', child: Text('Fallecido')),
              ],
              onChanged: submitting
                  ? null
                  : (v) => setState(() => _status = v ?? 'active'),
            ),
            const SizedBox(height: _fieldGap),
            TextFormField(
              controller: _notes,
              enabled: !submitting,
              style: _fieldTextStyle(context),
              decoration: _decoration(
                context,
                'Notas',
                hint: 'Opcional',
              ),
              maxLines: 3,
            ),
            if (submitError != null) ...[
              const SizedBox(height: 20),
              Text(
                submitError,
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: submitting ? null : () => _submit(vm),
                child: submitting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(isEdit ? 'Guardar cambios' : 'Crear'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
