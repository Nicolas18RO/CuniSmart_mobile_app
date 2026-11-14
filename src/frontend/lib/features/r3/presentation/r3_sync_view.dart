import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/local/r3_conflict_resolution.dart';
import '../../../services/auth_service.dart';
import '../../../services/r3_hydration_service.dart';

class R3SyncView extends StatefulWidget {
  const R3SyncView({super.key});

  @override
  State<R3SyncView> createState() => _R3SyncViewState();
}

class _R3SyncViewState extends State<R3SyncView> {
  bool _busy = false;
  String? _message;
  final _adjustment = TextEditingController();

  @override
  void dispose() {
    _adjustment.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      if (mounted) setState(() => _message = message);
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'No se pudo completar. Verifica la sesión y la conexión.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<R3HydrationService>();
    final auth = context.read<AuthService>();
    final generation = auth.generation;
    final owner = auth.ownerId;
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización R3')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await service.refresh();
                      return 'Consulta remota completada.';
                    }),
            child: const Text('Consultar datos remotos'),
          ),
          if (_message != null)
            Semantics(liveRegion: true, child: Text(_message!)),
          FutureBuilder(
            future: service.coverage(),
            builder: (context, result) {
              if (auth.generation != generation ||
                  auth.ownerId != owner ||
                  !auth.localDataUnlocked ||
                  !result.hasData) {
                return const SizedBox.shrink();
              }
              String label(String? value) => switch (value) {
                    'COMPLETE' => 'completa',
                    'PARTIAL' => 'parcial',
                    'IN_PROGRESS' => 'en curso',
                    'FAILED' => 'fallida',
                    'STALE' => 'desactualizada',
                    _ => 'sin consultar',
                  };
              return Text(
                "Parentesco: ${label(result.data!['PARENT_LINK'])}. "
                "Eventos: ${label(result.data!['REPRODUCTIVE_EVENT'])}.",
              );
            },
          ),
          FutureBuilder(
            future: service.conflicts(),
            builder: (context, result) {
              if (auth.generation != generation ||
                  auth.ownerId != owner ||
                  !auth.localDataUnlocked) {
                return const SizedBox.shrink();
              }
              if (result.hasError) {
                return const Text('Conflictos no disponibles.');
              }
              final conflicts = result.data;
              if (conflicts == null) return const LinearProgressIndicator();
              if (conflicts.isEmpty) {
                return const Text('Sin conflictos abiertos.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in conflicts)
                    ExpansionTile(
                      title: Text(row.read<String>('entity') == 'PARENT_LINK'
                          ? 'Conflicto de parentesco'
                          : 'Conflicto reproductivo'),
                      subtitle: Text(
                          'Versión remota ${row.read<int>('remote_version')}'),
                      children: [
                        Text(
                            'Base: ${row.readNullable<String>('base') ?? 'Desconocida'}'),
                        Text(
                            'Local: ${row.readNullable<String>('local') ?? 'Desconocido'}'),
                        Text('Remoto: ${row.read<String>('remote')}'),
                        if (row.read<String>('state') == 'BLOCKED')
                          const Text(
                              'Bloqueado. Consulta la evidencia actualizada.')
                        else ...[
                          for (final decision in R3Resolution.values)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                        String? adjustment;
                                        if (decision == R3Resolution.manual) {
                                          _adjustment.clear();
                                          adjustment = await showDialog<String>(
                                            context: context,
                                            builder: (dialog) => AlertDialog(
                                              title: const Text(
                                                  'Ajustar resolución'),
                                              content: TextField(
                                                controller: _adjustment,
                                                decoration: InputDecoration(
                                                    labelText: row.read<String>(
                                                                'entity') ==
                                                            'PARENT_LINK'
                                                        ? 'UUID del progenitor'
                                                        : 'Notas de la monta'),
                                              ),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(dialog),
                                                    child:
                                                        const Text('Cancelar')),
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(dialog,
                                                            _adjustment.text),
                                                    child:
                                                        const Text('Aceptar')),
                                              ],
                                            ),
                                          );
                                          if (adjustment == null) {
                                            return 'Ajuste cancelado.';
                                          }
                                        }
                                        if (auth.generation != generation ||
                                            auth.ownerId != owner) {
                                          return 'La cuenta cambió.';
                                        }
                                        final done = await service.resolve(
                                            row.read<String>('uuid'), decision,
                                            adjustment: adjustment);
                                        return done
                                            ? 'Resolución guardada.'
                                            : 'La resolución requiere evidencia o revisión adicional.';
                                      }),
                              child: Text(switch (decision) {
                                R3Resolution.remote => 'Conservar remoto',
                                R3Resolution.local => 'Conservar local',
                                R3Resolution.manual => 'Ajustar datos',
                              }),
                            ),
                        ],
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
