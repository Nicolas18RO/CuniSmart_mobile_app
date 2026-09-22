import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/models/sync_status.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';
import 'package:frontend/views/rabbits/rabbit_detail_view.dart';
import 'package:frontend/views/rabbits/rabbit_qr_view.dart';

void main() {
  const rabbit = Rabbit(
    id: 1,
    uuid: '11111111-1111-1111-1111-111111111111',
    name: 'Luna',
    breed: 'Rex',
    sex: 'female',
    birthDate: '2024-01-15',
    weight: 2.5,
    status: 'active',
    notes: 'Mansa',
    version: 1,
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  );

  testWidgets('ficha shows complete animal fields and TalkBack labels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RabbitViewModel(
          RabbitService(
            ApiClient(
              httpClient: MockClient(
                (_) async => http.Response('[]', 200),
              ),
            ),
            RabbitLocalStore(AppDatabase.memory()),
          ),
        ),
        child: const MaterialApp(home: RabbitDetailView(rabbit: rabbit)),
      ),
    );

    expect(find.text('Luna'), findsWidgets);
    expect(find.text('Rex'), findsOneWidget);
    expect(find.text('Hembra'), findsOneWidget);
    expect(find.text('2024-01-15'), findsOneWidget);
    expect(find.text('2.5 kg'), findsOneWidget);
    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Mansa'), findsOneWidget);
    expect(find.text('11111111-1111-1111-1111-111111111111'), findsOneWidget);
    expect(find.text('Sincronizado'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
    expect(find.text('Ver código QR'), findsWidgets);
    expect(find.byTooltip('Ver código QR'), findsOneWidget);
    expect(find.bySemanticsLabel('Sexo: Hembra'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Identificador: 11111111-1111-1111-1111-111111111111',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('ficha in CONFLICT shows keep-remote and keep-local actions', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    const conflictRabbit = Rabbit(
      id: 1,
      uuid: '11111111-1111-1111-1111-111111111111',
      name: 'Luna',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-01-15',
      weight: 2.5,
      status: 'active',
      notes: 'telefono',
      version: 1,
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
      syncStatus: RabbitSyncStatus.conflict,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RabbitViewModel(
          RabbitService(
            ApiClient(
              httpClient: MockClient(
                (_) async => http.Response('[]', 200),
              ),
            ),
            RabbitLocalStore(AppDatabase.memory()),
          ),
        ),
        child:
            const MaterialApp(home: RabbitDetailView(rabbit: conflictRabbit)),
      ),
    );

    expect(find.text('Conflicto'), findsOneWidget);
    expect(
      find.text(
        'Este conejo se modificó en otro lugar. Elige qué versión conservar.',
      ),
      findsOneWidget,
    );
    expect(find.text('Conservar versión del servidor'), findsOneWidget);
    expect(find.text('Conservar mis cambios'), findsOneWidget);
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Eliminar'), findsNothing);
    expect(
      find.bySemanticsLabel('Conservar versión del servidor'),
      findsWidgets,
    );
    expect(find.bySemanticsLabel('Conservar mis cambios'), findsWidgets);
    handle.dispose();
  });

  testWidgets('ficha Ver código QR opens the QR screen with TalkBack label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RabbitViewModel(
          RabbitService(
            ApiClient(
              httpClient: MockClient(
                (_) async => http.Response('[]', 200),
              ),
            ),
            RabbitLocalStore(AppDatabase.memory()),
          ),
        ),
        child: const MaterialApp(home: RabbitDetailView(rabbit: rabbit)),
      ),
    );

    await tester.tap(find.byTooltip('Ver código QR'));
    await tester.pumpAndSettle();

    expect(find.byType(RabbitQrView), findsOneWidget);
    expect(find.text('Código QR'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Código QR de Luna, identificador 11111111-1111-1111-1111-111111111111',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
