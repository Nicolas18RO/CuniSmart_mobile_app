import '../../../domain/genealogy/kinship.dart';
import '../../../domain/genealogy/parent_link.dart';
import '../../../models/rabbit.dart';
import '../../../models/sync_status.dart';

enum LocalRabbitAvailability { available, pendingCreate, unavailable, deleted }

enum ReproductiveRole { male, female }

enum GenealogyCoverage { complete, incomplete, unavailable, inconsistent }

class LocalRabbitReference {
  const LocalRabbitReference(this.uuid, this.rabbit);
  final String uuid;
  final Rabbit? rabbit;

  LocalRabbitAvailability get availability {
    final row = rabbit;
    if (row == null) return LocalRabbitAvailability.unavailable;
    if (row.deletedAt != null) return LocalRabbitAvailability.deleted;
    if (row.syncStatus == RabbitSyncStatus.pendingCreate) {
      return LocalRabbitAvailability.pendingCreate;
    }
    return LocalRabbitAvailability.available;
  }

  bool get usable =>
      availability == LocalRabbitAvailability.available ||
      availability == LocalRabbitAvailability.pendingCreate;
}

/// Identity and timestamps from E6.2, with the existing domain edge.
class LocalParentRelation {
  const LocalParentRelation({
    required this.uuid,
    required this.ownerId,
    required this.link,
    required this.child,
    required this.parent,
    required this.createdAt,
    required this.updatedAt,
  });
  final String uuid;
  final int ownerId;
  final ParentLink link;
  final LocalRabbitReference child;
  final LocalRabbitReference parent;
  final String createdAt;
  final String updatedAt;
}

/// Local facts, without fabricated remote IDs, names or kinship estimates.
class LocalReproductiveRecord {
  const LocalReproductiveRecord({
    required this.uuid,
    required this.ownerId,
    required this.male,
    required this.female,
    required this.matingDate,
    required this.estimatedBirthDate,
    required this.notes,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  final String uuid;
  final int ownerId;
  final LocalRabbitReference male;
  final LocalRabbitReference female;
  final String matingDate;
  final String estimatedBirthDate;
  final String notes;
  final int version;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
}

class LocalCalendarEntry {
  const LocalCalendarEntry(this.event, this.daysRemaining);
  final LocalReproductiveRecord event;
  final int daysRemaining;

  String get calendarState => switch (daysRemaining) {
        < 0 => 'OVERDUE',
        0 => 'DUE_TODAY',
        _ => 'UPCOMING',
      };
}

class LocalGenealogy {
  LocalGenealogy({
    required this.coverage,
    required Iterable<String> roots,
    required Map<String, LocalRabbitReference> nodes,
    required Iterable<LocalParentRelation> links,
    required Iterable<LocalParentRelation> deletedLinks,
    required Map<String, List<ParentRole>> unknownParents,
    required Iterable<String> confirmedFounders,
    required this.depthExplored,
    required this.depthLimited,
    required this.hasCycle,
    required this.evaluation,
  })  : roots = List.unmodifiable(roots),
        nodes = Map.unmodifiable(nodes),
        links = List.unmodifiable(links),
        deletedLinks = List.unmodifiable(deletedLinks),
        unknownParents = Map.unmodifiable(unknownParents.map((uuid, roles) =>
            MapEntry(uuid, List<ParentRole>.unmodifiable(roles)))),
        confirmedFounders = Set.unmodifiable(confirmedFounders);

  final GenealogyCoverage coverage;
  final List<String> roots;
  final Map<String, LocalRabbitReference> nodes;
  final List<LocalParentRelation> links;
  final List<LocalParentRelation> deletedLinks;
  final Map<String, List<ParentRole>> unknownParents;
  final Set<String> confirmedFounders;
  final int depthExplored;
  final bool depthLimited;
  final bool hasCycle;
  final KinshipResult? evaluation;

  Set<String> get unavailable => Set.unmodifiable(
        nodes.values.where((node) => !node.usable).map((node) => node.uuid),
      );
}
