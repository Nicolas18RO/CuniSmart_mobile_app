import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';
import 'package:frontend/views/rabbits/rabbit_detail_view.dart';
import 'package:frontend/voice/engine/voice_ai_engine.dart';

const _luna = Rabbit(
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

void main() {
  test('ficha speech covers name, breed, sex, date, weight, status and notes',
      () {
    final spoken = VoiceAIEngine.fichaSpeech(_luna);
    expect(spoken, contains('Luna'));
    expect(spoken, contains('Raza Rex'));
    expect(spoken, contains('Sexo hembra'));
    expect(spoken, contains('Nacido el 2024-01-15'));
    expect(spoken, contains('Peso'));
    expect(spoken, contains('2,5'));
    expect(spoken, contains('Estado activo'));
    expect(spoken, contains('Observaciones'));
    expect(spoken, contains('Mansa'));
    expect(spoken.indexOf('Peso'), lessThan(spoken.indexOf('Estado')));
  });

  test('ficha speech says sin peso and sin notas when those fields are empty',
      () {
    const pepe = Rabbit(
      id: 2,
      uuid: '22222222-2222-2222-2222-222222222222',
      name: 'Pepe',
      breed: 'NZ',
      sex: 'male',
      birthDate: '2023-05-01',
      status: 'sold',
      notes: '',
      version: 1,
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
    );
    final spoken = VoiceAIEngine.fichaSpeech(pepe);
    expect(spoken, contains('sin peso'));
    expect(spoken, contains('sin notas'));
    expect(spoken, contains('Estado vendido'));
    expect(spoken, contains('Sexo macho'));
  });

  testWidgets('ficha TalkBack labels follow the expected field order', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RabbitViewModel(
          RabbitService(
            ApiClient(
              httpClient: MockClient((_) async => http.Response('[]', 200)),
            ),
            RabbitLocalStore(AppDatabase.memory()),
          ),
        ),
        child: const MaterialApp(home: RabbitDetailView(rabbit: _luna)),
      ),
    );

    expect(find.bySemanticsLabel('Nombre: Luna'), findsOneWidget);
    expect(find.bySemanticsLabel('Raza: Rex'), findsOneWidget);
    expect(find.bySemanticsLabel('Sexo: Hembra'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Fecha de nacimiento: 2024-01-15'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Peso: 2.5 kg'), findsOneWidget);
    expect(find.bySemanticsLabel('Estado: Activo'), findsOneWidget);
    expect(find.bySemanticsLabel('Observaciones: Mansa'), findsOneWidget);

    double orderOf(String label) {
      final key = tester.getSemantics(find.bySemanticsLabel(label)).sortKey;
      expect(key, isA<OrdinalSortKey>());
      return (key! as OrdinalSortKey).order;
    }

    expect(orderOf('Nombre: Luna'), lessThan(orderOf('Raza: Rex')));
    expect(orderOf('Raza: Rex'), lessThan(orderOf('Sexo: Hembra')));
    expect(
      orderOf('Sexo: Hembra'),
      lessThan(orderOf('Fecha de nacimiento: 2024-01-15')),
    );
    expect(
      orderOf('Fecha de nacimiento: 2024-01-15'),
      lessThan(orderOf('Peso: 2.5 kg')),
    );
    expect(orderOf('Peso: 2.5 kg'), lessThan(orderOf('Estado: Activo')));
    expect(
      orderOf('Estado: Activo'),
      lessThan(orderOf('Observaciones: Mansa')),
    );
    handle.dispose();
  });
}
