import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/state/async_view_state.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/features/r3/application/r3_use_cases.dart';
import 'package:frontend/features/r3/data/local_r3_repository.dart';
import 'package:frontend/features/r3/presentation/r3_view_model.dart';
import 'package:frontend/features/r3/presentation/r3_presentation_utils.dart';
import 'package:frontend/features/r3/domain/r3_local_results.dart';
import 'package:frontend/features/r3/domain/r3_models.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';
import 'package:frontend/voice/engine/r3_voice_facade.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'fake_r3_repository.dart';

import 'e6_2_local_persistence_test.dart'
    show seed, child, father, mother, animal;

void main() {
  testWidgets(
      'coverage announces a cycle, limited depth and missing references',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final graph = LocalGenealogy(
        coverage: GenealogyCoverage.inconsistent,
        roots: [child],
        nodes: {child: const LocalRabbitReference(child, null)},
        links: [],
        deletedLinks: [],
        unknownParents: {},
        confirmedFounders: [],
        depthExplored: 2,
        depthLimited: true,
        hasCycle: true,
        evaluation: null);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: R3CoverageSummary(graph: graph))));
    expect(
        find.bySemanticsLabel(
            RegExp('Copia local.*Ciclo genealógico detectado')),
        findsOneWidget);
    expect(find.textContaining('Referencias sin ficha utilizable: 1'),
        findsOneWidget);
    expect(find.textContaining('límite de exploración'), findsOneWidget);
    semantics.dispose();
  });

  test('late results and stale submit callbacks are discarded', () async {
    var generation = 1;
    final source = _DelayedRepository();
    final vm =
        R3ViewModel(R3UseCases(source), sessionGeneration: () => generation);
    addTearDown(vm.dispose);
    final pending = vm.loadPedigree(child);
    expect(vm.pedigreeState, isA<AsyncLoading>());
    generation++;
    vm.invalidateSession();
    source.response.complete(const Pedigree(
        ancestors: [],
        descendants: [],
        integrity: 'VALID',
        integrityIssues: [],
        links: []));
    await pending;
    expect(vm.pedigreeState, isA<AsyncInitial>());
    expect(
        await vm.setParent(
            child: child,
            role: 'FATHER',
            parent: father,
            expectedGeneration: 1),
        isFalse);
  });
  test(
      'R3 shares local writes, reads and voice while account changes clear results',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await seed(db);
    var owner = 1;
    final api = ApiClient(httpClient: MockClient((request) async {
      switch (request.url.path) {
        case '/api/auth/login/':
          return http.Response('{"access":"a","refresh":"r"}', 200);
        case '/api/auth/session/':
          return http.Response(
              '{"user":{"id":$owner,"is_verified":true},"settings":{"biometric_enabled":false}}',
              200);
        default:
          fail('Unexpected HTTP request: ${request.url.path}');
      }
    }));
    final auth = AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
        readBootTime: () async =>
            (bootCount: 1, elapsedMilliseconds: 0, installationId: 'test'));
    addTearDown(() => auth.clearSession(notify: false));
    await auth.login(email: 'a@test.invalid', password: 'password');
    auth.localDataUnlocked = true;
    auth.markDisconnected();
    expect(auth.remoteVerified, isFalse);
    final useCases = R3UseCases(
        LocalR3Repository(db, auth, clock: () => DateTime(2024, 2, 29)));
    final vm = R3ViewModel(useCases,
        sessionGeneration: () => auth.generation,
        sessionUnlocked: () => auth.localDataUnlocked);
    addTearDown(vm.dispose);
    expect(await vm.setParent(child: child, role: 'FATHER', parent: father),
        isTrue);
    final pedigree = await useCases.loadPedigree(child);
    expect(pedigree.local, isNotNull);
    expect(pedigree.father!.uuid, father);
    final answer = await R3VoiceFacade(useCases,
        sessionGeneration: () => auth.generation,
        sessionUnlocked: () =>
            auth.localDataUnlocked).answer(
        'quién es el padre de luna', [animal(child).copyWith(name: 'Luna')]);
    expect(answer, contains('copia local'));
    final event = await useCases.createEvent(
        male: father, female: mother, date: '2024-01-29');
    final voice = R3VoiceFacade(useCases,
        sessionGeneration: () => auth.generation,
        sessionUnlocked: () => auth.localDataUnlocked);
    expect(
        await voice.answer('historial reproductivo de luna',
            [animal(mother, sex: 'female').copyWith(name: 'Luna')]),
        contains('última monta'));
    expect(
        await useCases.loadEvents(
            participant: father, role: ReproductiveRole.female),
        isEmpty);
    expect(
        (await useCases.loadEvents(
                participant: father, role: ReproductiveRole.male))
            .single
            .uuid,
        event.uuid);
    expect(event.estimatedBirthDate, '2024-02-29');
    expect(event.calendarState, 'DUE_TODAY');
    expect(
        (await useCases.loadCalendar('2024-02-29', '2024-02-29')).single.uuid,
        event.uuid);
    owner = 2;
    await auth.login(email: 'b@test.invalid', password: 'password');
    auth.localDataUnlocked = true;
    expect(vm.pedigreeState, isA<AsyncInitial>());
    expect(await useCases.loadEvents(), isEmpty);
    expect(
        await vm.saveEvent(
            event: event,
            male: father,
            female: mother,
            date: '2024-01-30',
            notes: 'wrong owner'),
        isFalse);
  });
}

class _DelayedRepository extends FakeR3Repository {
  final response = Completer<Pedigree>();

  @override
  Future<Pedigree> pedigree(String rabbitUuid) => response.future;
}
