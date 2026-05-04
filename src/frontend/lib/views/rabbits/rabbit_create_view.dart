import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/submit_state.dart';
import '../../viewmodels/rabbit_viewmodel.dart';

class RabbitCreateView extends StatefulWidget {
  const RabbitCreateView({super.key});

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

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _birthDate.dispose();
    _weight.dispose();
    _notes.dispose();
    super.dispose();
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
          const SnackBar(content: Text('Weight must be a number')),
        );
        return;
      }
    }

    vm.clearSubmitError();

    final ok = await vm.createRabbit(
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

    return Scaffold(
      appBar: AppBar(title: const Text('New rabbit')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              enabled: !submitting,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _breed,
              enabled: !submitting,
              decoration: const InputDecoration(labelText: 'Breed'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _sex,
              decoration: const InputDecoration(labelText: 'Sex'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
              ],
              onChanged: submitting
                  ? null
                  : (v) => setState(() => _sex = v ?? 'male'),
            ),
            TextFormField(
              controller: _birthDate,
              enabled: !submitting,
              decoration: const InputDecoration(
                labelText: 'Birth date (YYYY-MM-DD)',
                hintText: '2025-01-15',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _weight,
              enabled: !submitting,
              decoration: const InputDecoration(
                labelText: 'Weight (kg, optional)',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'sold', child: Text('Sold')),
                DropdownMenuItem(value: 'deceased', child: Text('Deceased')),
              ],
              onChanged: submitting
                  ? null
                  : (v) => setState(() => _status = v ?? 'active'),
            ),
            TextFormField(
              controller: _notes,
              enabled: !submitting,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 3,
            ),
            if (submitError != null) ...[
              const SizedBox(height: 16),
              Text(
                submitError,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: submitting ? null : () => _submit(vm),
              child: submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
