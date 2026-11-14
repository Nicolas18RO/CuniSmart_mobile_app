import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/features/r3/application/r3_use_cases.dart';
import 'package:frontend/features/r3/domain/r3_models.dart';
import 'package:frontend/features/r3/presentation/genealogy_views.dart';
import 'package:frontend/features/r3/presentation/r3_view_model.dart';
import 'package:frontend/features/r3/presentation/reproductive_views.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';

import 'fake_r3_repository.dart';

void main() {
  late AppDatabase db;
  late RabbitViewModel rabbitVm;
  late FakeR3Repository repo;
  late R3ViewModel r3Vm;

  const rabbits = [
    Rabbit(
        id: 1,
        uuid: '00000000-0000-0000-0000-000000000001',
        name: 'Luna',
        breed: 'Rex',
        sex: 'female',
        birthDate: '2025-01-01',
        status: 'active',
        notes: '',
        version: 1,
        createdAt: 'x',
        updatedAt: 'x'),
    Rabbit(
        id: 2,
        uuid: '00000000-0000-0000-0000-000000000002',
        name: 'Bruno',
        breed: 'Rex',
        sex: 'male',
        birthDate: '2025-01-01',
        status: 'active',
        notes: '',
        version: 1,
        createdAt: 'x',
        updatedAt: 'x'),
  ];

  setUp(() async {
    db = AppDatabase.memory();
    addTearDown(db.close);
    final raw = jsonEncode(rabbits
        .map((r) => {
              'id': r.id,
              'uuid': r.uuid,
              'user': 1,
              'name': r.name,
              'breed': r.breed,
              'sex': r.sex,
              'birth_date': r.birthDate,
              'weight': null,
              'status': r.status,
              'notes': r.notes,
              'version': r.version,
              'created_at': r.createdAt,
              'updated_at': r.updatedAt,
              'deleted_at': null,
            })
        .toList());
    rabbitVm = RabbitViewModel(RabbitService(
      ApiClient(
          baseUrl: 'http://test',
          httpClient: MockClient((_) async => http.Response(raw, 200))),
      RabbitLocalStore(db),
    ));
    await rabbitVm.loadRabbits();
    repo = FakeR3Repository();
    r3Vm = R3ViewModel(R3UseCases(repo));
  });

  Widget app(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<RabbitViewModel>.value(value: rabbitVm),
          ChangeNotifierProvider<R3ViewModel>.value(value: r3Vm),
        ],
        child: MaterialApp(home: child),
      );

  testWidgets('genealogy shows known and unknown parents plus generations',
      (tester) async {
    repo.pedigreeValue = const Pedigree(
      father: PedigreeAnimal(
          uuid: 'p', name: 'Bruno', sex: 'male', generation: 1, deleted: false),
      ancestors: [
        PedigreeAnimal(
            uuid: 'p',
            name: 'Bruno',
            sex: 'male',
            generation: -2,
            relationship: 'GRANDSON',
            deleted: false)
      ],
      descendants: [],
      integrity: 'VALID',
      integrityIssues: [],
      links: [PedigreeLink(role: 'FATHER', version: 1)],
    );
    await tester.pumpWidget(app(GenealogyView(rabbit: rabbits[0])));
    await tester.pumpAndSettle();
    expect(find.text('Padre actual: Bruno'), findsOneWidget);
    expect(find.text('Madre actual: Desconocido'), findsOneWidget);
    expect(find.text('Árbol por generaciones'), findsOneWidget);
    expect(find.textContaining('Nieto'), findsOneWidget);
    expect(find.textContaining('Generación -2'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Consultar parentesco'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Consultar parentesco'), findsOneWidget);
  });

  testWidgets('kinship explains NO_CALCULABLE without zero', (tester) async {
    await r3Vm.evaluate(rabbits[0].uuid, rabbits[1].uuid);
    await tester.pumpWidget(app(KinshipView(initialRabbit: rabbits[0])));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('No hay información suficiente'), findsOneWidget);
    expect(find.textContaining('no equivale a cero'), findsOneWidget);
  });

  testWidgets('independent founders explain model assumption and zero',
      (tester) async {
    repo.kinshipValue = const KinshipEvaluation(
      status: 'CALCULABLE',
      relationshipCoefficient: '0',
      expectedInbreeding: '0',
      minimumKnownInbreeding: '0',
      isExact: true,
      relationshipType: 'UNRELATED',
      riskLevel: 'SIN_ADVERTENCIA',
      commonAncestors: [],
      reason: null,
      independenceAssumptionApplied: true,
      declaredFounders: ['Bruno', 'Luna'],
    );
    await r3Vm.evaluate(rabbits[1].uuid, rabbits[0].uuid);
    await tester.pumpWidget(app(KinshipView(initialRabbit: rabbits[1])));
    await tester.pumpAndSettle();
    expect(find.text('Sin parentesco detectado'), findsOneWidget);
    expect(find.textContaining('0 %'), findsWidgets);
    expect(find.textContaining('Líneas fundadoras declaradas'), findsOneWidget);
    expect(find.textContaining('no garantiza ausencia de parentesco biológico'),
        findsOneWidget);
  });

  testWidgets('kinship presents partial known minimum instead of no calculable',
      (tester) async {
    repo.kinshipValue = const KinshipEvaluation(
      status: 'PARTIAL',
      relationshipCoefficient: '0.5',
      expectedInbreeding: null,
      minimumKnownInbreeding: '0.25',
      relationshipType: 'FATHER_DAUGHTER',
      riskLevel: 'ALTO',
      commonAncestors: [
        KinshipAncestor(
            uuid: 'pepe', name: 'Pepe', n1: 0, n2: 1, contribution: '0.5')
      ],
      reason: 'INFORMACIÓN_GENEALÓGICA_INSUFICIENTE',
    );
    await r3Vm.evaluate(rabbits[1].uuid, rabbits[0].uuid);
    await tester.pumpWidget(app(KinshipView(initialRabbit: rabbits[1])));
    await tester.pumpAndSettle();
    expect(find.textContaining('mínimo conocido: 50 %'), findsOneWidget);
    expect(find.textContaining('mínima conocida: 25 %'), findsOneWidget);
    expect(find.text('Riesgo: ALTO'), findsOneWidget);
    expect(find.textContaining('Ancestros comunes: Pepe'), findsOneWidget);
    expect(find.textContaining('No hay información suficiente'), findsNothing);
  });

  testWidgets('reproductive list and calendar use backend-derived status',
      (tester) async {
    repo.eventValue();
    await tester.pumpWidget(app(const ReproductiveEventListView()));
    await tester.pumpAndSettle();
    expect(find.text('Bruno × Luna'), findsOneWidget);
    expect(find.textContaining('Próximo'), findsOneWidget);
    expect(find.textContaining('Parto previsto hoy'), findsOneWidget);
    expect(find.textContaining('Fecha prevista vencida'), findsOneWidget);
    await tester.tap(find.byTooltip('Calendario reproductivo'));
    await tester.pumpAndSettle();
    expect(find.text('Calendario reproductivo'), findsOneWidget);
    expect(find.text('Parto probable: 2026-11-20'), findsOneWidget);
  });

  testWidgets('event form and detail expose create edit and delete flows',
      (tester) async {
    repo.eventValue();
    await tester
        .pumpWidget(app(const ReproductiveEventFormView(rabbits: rabbits)));
    expect(find.text('Registrar monta'), findsWidgets);
    expect(find.text('Macho'), findsOneWidget);
    expect(find.text('Hembra'), findsOneWidget);
    expect(find.text('Notas opcionales'), findsOneWidget);
    expect(find.textContaining('Fecha probable'), findsNothing);

    await tester.pumpWidget(app(ReproductiveEventDetailView(
        event: repo.eventValues.first, rabbits: rabbits)));
    expect(find.text('Editar fecha o notas'), findsOneWidget);
    expect(find.text('Eliminar evento'), findsOneWidget);
    expect(
        find.textContaining('No hay información suficiente'), findsOneWidget);
  });
}

extension on FakeR3Repository {
  void eventValue() {
    const kinship = KinshipEvaluation(
        status: 'NO_CALCULABLE',
        relationshipCoefficient: null,
        expectedInbreeding: null,
        riskLevel: 'NO_CALCULABLE',
        commonAncestors: [],
        reason: 'insuficiente');
    eventValues = const [
      ReproductiveEvent(
        uuid: 'event',
        maleUuid: '00000000-0000-0000-0000-000000000002',
        maleName: 'Bruno',
        femaleUuid: '00000000-0000-0000-0000-000000000001',
        femaleName: 'Luna',
        matingDate: '2026-10-20',
        estimatedBirthDate: '2026-11-20',
        notes: '',
        version: 1,
        calendarState: 'UPCOMING',
        daysRemaining: 11,
        kinship: kinship,
      ),
      ReproductiveEvent(
          uuid: 'today',
          maleUuid: 'm',
          maleName: 'M2',
          femaleUuid: 'f',
          femaleName: 'F2',
          matingDate: '2026-10-01',
          estimatedBirthDate: '2026-11-01',
          notes: '',
          version: 1,
          calendarState: 'DUE_TODAY',
          daysRemaining: 0,
          kinship: kinship),
      ReproductiveEvent(
          uuid: 'late',
          maleUuid: 'm',
          maleName: 'M3',
          femaleUuid: 'f',
          femaleName: 'F3',
          matingDate: '2026-09-01',
          estimatedBirthDate: '2026-10-02',
          notes: '',
          version: 1,
          calendarState: 'OVERDUE',
          daysRemaining: -38,
          kinship: kinship),
    ];
  }
}
