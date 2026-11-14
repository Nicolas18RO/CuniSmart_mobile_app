import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/state/async_view_state.dart';
import 'package:frontend/core/state/submit_state.dart';
import 'package:frontend/features/r3/application/r3_use_cases.dart';
import 'package:frontend/features/r3/domain/r3_models.dart';
import 'package:frontend/features/r3/presentation/r3_view_model.dart';

import 'fake_r3_repository.dart';

void main() {
  test('pedigree version is scoped to the requested child', () {
    const pedigree = Pedigree(
      ancestors: [],
      descendants: [],
      integrity: 'VALID',
      integrityIssues: [],
      links: [
        PedigreeLink(role: 'FATHER', version: 4, childUuid: 'other'),
        PedigreeLink(role: 'FATHER', version: 2, childUuid: 'max'),
      ],
    );
    expect(pedigree.versionFor('FATHER', childUuid: 'max'), 2);
    expect(pedigree.versionFor('MOTHER', childUuid: 'max'), isNull);
  });

  test('pedigree moves loading to success and exposes empty state data',
      () async {
    final vm = R3ViewModel(R3UseCases(FakeR3Repository()));
    final future = vm.loadPedigree('rabbit');
    expect(vm.pedigreeState, isA<AsyncLoading<Pedigree>>());
    await future;
    expect(vm.pedigreeState, isA<AsyncSuccess<Pedigree>>());
  });

  test('NO_CALCULABLE remains a successful nonnumeric result', () async {
    final vm = R3ViewModel(R3UseCases(FakeR3Repository()));
    await vm.evaluate('a', 'b');
    final state = vm.kinshipState as AsyncSuccess<KinshipEvaluation>;
    expect(state.data.calculable, isFalse);
    expect(state.data.expectedInbreeding, isNull);
  });

  test('409 becomes visible submit conflict', () async {
    final repo = FakeR3Repository()..conflict();
    final vm = R3ViewModel(R3UseCases(repo));
    final ok = await vm.setParent(child: 'c', role: 'FATHER', parent: 'p');
    expect(ok, isFalse);
    expect(vm.submitState, isA<SubmitFailed>());
    expect(
        (vm.submitState as SubmitFailed).message, contains('otro dispositivo'));
  });

  test('events expose empty and error states', () async {
    final repo = FakeR3Repository();
    final vm = R3ViewModel(R3UseCases(repo));
    await vm.loadEvents();
    expect((vm.eventsState as AsyncSuccess<List<ReproductiveEvent>>).data,
        isEmpty);
    repo.error = Exception('offline');
    await vm.loadEvents();
    expect(vm.eventsState, isA<AsyncError<List<ReproductiveEvent>>>());
  });
}
