import '../../models/sync_status.dart';

/// Role of a progenitor. Values match the approved R3 contract.
enum ParentRole {
  father('FATHER'),
  mother('MOTHER');

  const ParentRole(this.storageValue);

  final String storageValue;

  static ParentRole? fromStorage(String raw) {
    return switch (raw) {
      'FATHER' => ParentRole.father,
      'MOTHER' => ParentRole.mother,
      _ => null,
    };
  }
}

enum ParentLinkViolation {
  missingUuid,
  selfParent,
  parentDeleted,
  childDeleted,
  differentOwner,
  fatherMustBeMale,
  motherMustBeFemale,
  sameAnimalBothRoles,
  secondFather,
  secondMother,
  directCycle,
  indirectCycle,
  invalidVersion,
  versionConflict,
  founderHasParents,
}

/// Animal facts the genealogy rules need. Not a second rabbit model.
class GenealogySubject {
  const GenealogySubject({
    required this.uuid,
    required this.sex,
    required this.ownerId,
    this.deleted = false,
    this.knowledge = 'UNKNOWN',
  });

  final String uuid;
  final String sex;
  final int ownerId;
  final bool deleted;
  final String knowledge;

  bool get hasUuid => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(uuid);
}

/// One father or mother edge. Identity stays on the rabbit UUID.
class ParentLink {
  const ParentLink({
    required this.childUuid,
    required this.parentUuid,
    required this.role,
    required this.version,
    required this.syncStatus,
    this.deletedAt,
  });

  final String childUuid;
  final String parentUuid;
  final ParentRole role;
  final int version;
  final DateTime? deletedAt;
  final RabbitSyncStatus syncStatus;

  bool get isActive => deletedAt == null;
}

class ParentLinkDecision {
  const ParentLinkDecision._({this.link, this.violation});

  final ParentLink? link;
  final ParentLinkViolation? violation;

  bool get accepted => violation == null && link != null;
}

class ParentLinkRules {
  const ParentLinkRules._();

  static const String male = 'male';
  static const String female = 'female';

  static ParentLinkDecision clear({
    required GenealogySubject child,
    required GenealogySubject parent,
    required ParentRole role,
    required List<ParentLink> links,
    required Object? version,
    required DateTime deletedAt,
  }) {
    if (!child.hasUuid || !parent.hasUuid) {
      return const ParentLinkDecision._(
          violation: ParentLinkViolation.missingUuid);
    }
    if (child.deleted) {
      return const ParentLinkDecision._(
          violation: ParentLinkViolation.childDeleted);
    }
    if (child.ownerId != parent.ownerId) {
      return const ParentLinkDecision._(
          violation: ParentLinkViolation.differentOwner);
    }
    if (version == null) {
      return const ParentLinkDecision._(
          violation: ParentLinkViolation.versionConflict);
    }
    if (version is! int || version < 1 || version > 2147483647) {
      return const ParentLinkDecision._(
          violation: ParentLinkViolation.invalidVersion);
    }
    for (final link in links) {
      if (link.isActive &&
          link.childUuid == child.uuid &&
          link.role == role &&
          link.parentUuid == parent.uuid &&
          link.version == version) {
        return ParentLinkDecision._(
            link: ParentLink(
          childUuid: link.childUuid,
          parentUuid: link.parentUuid,
          role: role,
          version: version + 1,
          syncStatus: RabbitSyncStatus.pendingDelete,
          deletedAt: deletedAt,
        ));
      }
    }
    return const ParentLinkDecision._(
        violation: ParentLinkViolation.versionConflict);
  }

  static ParentLinkDecision assign({
    required GenealogySubject child,
    required GenealogySubject parent,
    required ParentRole role,
    List<ParentLink> activeLinks = const [],
    Object? version,
  }) {
    if (version != null &&
        (version is! int || version < 1 || version > 2147483647)) {
      return const ParentLinkDecision._(
          violation: ParentLinkViolation.invalidVersion);
    }
    ParentLink? current;
    var previousVersion = 0;
    for (final link in activeLinks) {
      if (link.childUuid == child.uuid &&
          link.role == role &&
          link.version > previousVersion) {
        previousVersion = link.version;
      }
      if (link.isActive && link.childUuid == child.uuid && link.role == role) {
        current = link;
      }
    }
    if ((current != null && version != current.version) ||
        (current == null && version != null)) {
      return const ParentLinkDecision._(
          violation: ParentLinkViolation.versionConflict);
    }
    final violation = _violation(
      child: child,
      parent: parent,
      role: role,
      links: activeLinks,
    );
    if (violation != null) {
      return ParentLinkDecision._(violation: violation);
    }
    return ParentLinkDecision._(
      link: ParentLink(
        childUuid: child.uuid.trim(),
        parentUuid: parent.uuid.trim(),
        role: role,
        version: current == null ? previousVersion + 1 : current.version + 1,
        syncStatus: current == null
            ? RabbitSyncStatus.pendingCreate
            : RabbitSyncStatus.pendingUpdate,
      ),
    );
  }

  static ParentLinkViolation? _violation({
    required GenealogySubject child,
    required GenealogySubject parent,
    required ParentRole role,
    required List<ParentLink> links,
  }) {
    if (!child.hasUuid || !parent.hasUuid) {
      return ParentLinkViolation.missingUuid;
    }
    final childId = child.uuid.trim();
    final parentId = parent.uuid.trim();
    if (childId == parentId) return ParentLinkViolation.selfParent;
    if (child.deleted) return ParentLinkViolation.childDeleted;
    if (parent.deleted) return ParentLinkViolation.parentDeleted;
    if (child.knowledge == 'FOUNDER') {
      return ParentLinkViolation.founderHasParents;
    }
    if (child.ownerId != parent.ownerId) {
      return ParentLinkViolation.differentOwner;
    }
    if (_sameAnimalBothRoles(childId, parentId, role, links)) {
      return ParentLinkViolation.sameAnimalBothRoles;
    }
    final sexViolation = _sex(parent.sex, role);
    if (sexViolation != null) return sexViolation;
    return _cycle(childId, parentId, links);
  }

  static ParentLinkViolation? _sex(String sex, ParentRole role) {
    return switch (role) {
      ParentRole.father when sex != male =>
        ParentLinkViolation.fatherMustBeMale,
      ParentRole.mother when sex != female =>
        ParentLinkViolation.motherMustBeFemale,
      _ => null,
    };
  }

  static bool _sameAnimalBothRoles(
    String childId,
    String parentId,
    ParentRole role,
    List<ParentLink> links,
  ) {
    final other =
        role == ParentRole.father ? ParentRole.mother : ParentRole.father;
    return links.any(
      (link) =>
          link.isActive &&
          link.childUuid == childId &&
          link.role == other &&
          link.parentUuid == parentId,
    );
  }

  /// Walks progenitors of [parentId]. Distance 1 is a direct cycle.
  static ParentLinkViolation? _cycle(
    String childId,
    String parentId,
    List<ParentLink> links,
  ) {
    final parentsOf = <String, List<String>>{};
    for (final link in links) {
      if (!link.isActive) continue;
      parentsOf.putIfAbsent(link.childUuid, () => []).add(link.parentUuid);
    }
    final visited = <String>{};
    var frontier = <String>[parentId];
    var depth = 0;
    while (frontier.isNotEmpty) {
      final next = <String>[];
      for (final node in frontier) {
        if (!visited.add(node)) continue;
        for (final ancestor in parentsOf[node] ?? const <String>[]) {
          if (ancestor == childId) {
            return depth == 0
                ? ParentLinkViolation.directCycle
                : ParentLinkViolation.indirectCycle;
          }
          next.add(ancestor);
        }
      }
      depth++;
      frontier = next;
    }
    return null;
  }
}
