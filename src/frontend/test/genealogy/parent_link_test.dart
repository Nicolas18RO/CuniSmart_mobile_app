import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/domain/genealogy/parent_link.dart';
import 'package:frontend/models/sync_status.dart';

void main() {
  const child = GenealogySubject(
      uuid: '00000000-0000-0000-0000-000000000001', sex: 'male', ownerId: 1);
  const parent = GenealogySubject(
      uuid: '00000000-0000-0000-0000-000000000002', sex: 'male', ownerId: 1);
  test('assign replace and stale versions', () {
    final first = ParentLinkRules.assign(
        child: child, parent: parent, role: ParentRole.father);
    expect(first.accepted, isTrue);
    expect(first.link!.version, 1);
    final removed = ParentLinkRules.clear(
        child: child,
        parent: parent,
        role: ParentRole.father,
        links: [first.link!],
        version: 1,
        deletedAt: DateTime.utc(2026));
    expect(removed.accepted, isTrue);
    expect(removed.link!.isActive, isFalse);
    expect(removed.link!.version, 2);
    final restored = ParentLinkRules.assign(
        child: child,
        parent: parent,
        role: ParentRole.father,
        activeLinks: [removed.link!]);
    expect(restored.link!.version, 3);
    expect(
        ParentLinkRules.assign(
            child: child,
            parent: parent,
            role: ParentRole.father,
            activeLinks: [first.link!]).violation,
        ParentLinkViolation.versionConflict);
    final next = ParentLinkRules.assign(
        child: child,
        parent: parent,
        role: ParentRole.father,
        activeLinks: [first.link!],
        version: 1);
    expect(next.accepted, isTrue);
    expect(next.link!.version, 2);
    expect(next.link!.syncStatus, RabbitSyncStatus.pendingUpdate);
    for (final version in [true, 1.9, '1', 0, -1, 2147483648]) {
      expect(
          ParentLinkRules.assign(
                  child: child,
                  parent: parent,
                  role: ParentRole.father,
                  version: version)
              .violation,
          ParentLinkViolation.invalidVersion);
    }
  });
  test('UUID ownership sex deletion founder and self rules', () {
    const variants = [
      GenealogySubject(uuid: 'name', sex: 'male', ownerId: 1),
      GenealogySubject(
          uuid: '00000000-0000-0000-0000-000000000003',
          sex: 'male',
          ownerId: 2),
      GenealogySubject(
          uuid: '00000000-0000-0000-0000-000000000003',
          sex: 'female',
          ownerId: 1),
      GenealogySubject(
          uuid: '00000000-0000-0000-0000-000000000003',
          sex: 'male',
          ownerId: 1,
          deleted: true),
    ];
    for (final candidate in variants) {
      expect(
          ParentLinkRules.assign(
                  child: child, parent: candidate, role: ParentRole.father)
              .accepted,
          isFalse);
    }
    expect(
        ParentLinkRules.assign(
                child: child, parent: child, role: ParentRole.father)
            .violation,
        ParentLinkViolation.selfParent);
    for (final candidate in [
      GenealogySubject(
          uuid: child.uuid, sex: 'male', ownerId: 1, deleted: true),
      GenealogySubject(
          uuid: child.uuid, sex: 'male', ownerId: 1, knowledge: 'FOUNDER'),
    ]) {
      expect(
          ParentLinkRules.assign(
                  child: candidate, parent: parent, role: ParentRole.father)
              .accepted,
          isFalse);
    }
  });
  test('direct and indirect cycles are rejected', () {
    final link = ParentLink(
        childUuid: parent.uuid,
        parentUuid: child.uuid,
        role: ParentRole.father,
        version: 1,
        syncStatus: RabbitSyncStatus.synced);
    expect(
        ParentLinkRules.assign(
            child: child,
            parent: parent,
            role: ParentRole.father,
            activeLinks: [link]).violation,
        ParentLinkViolation.directCycle);
    const middle = '00000000-0000-0000-0000-000000000003';
    final indirect = [
      ParentLink(
          childUuid: parent.uuid,
          parentUuid: middle,
          role: ParentRole.father,
          version: 1,
          syncStatus: RabbitSyncStatus.synced),
      ParentLink(
          childUuid: middle,
          parentUuid: child.uuid,
          role: ParentRole.father,
          version: 1,
          syncStatus: RabbitSyncStatus.synced),
    ];
    expect(
        ParentLinkRules.assign(
                child: child,
                parent: parent,
                role: ParentRole.father,
                activeLinks: indirect)
            .violation,
        ParentLinkViolation.indirectCycle);
  });
}
