import 'r3_local_results.dart';

class PedigreeAnimal {
  const PedigreeAnimal({
    required this.uuid,
    required this.name,
    required this.sex,
    required this.generation,
    required this.deleted,
    this.genealogyKnowledge = 'UNKNOWN',
    this.relationship = 'RELATIVE',
  });

  final String uuid;
  final String name;
  final String sex;
  final int generation;
  final bool deleted;
  final String genealogyKnowledge;
  final String relationship;

  factory PedigreeAnimal.fromJson(Map<String, dynamic> json) => PedigreeAnimal(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? 'Sin nombre',
        sex: json['sex'] as String? ?? '',
        generation: (json['generation'] as num?)?.toInt() ?? 0,
        deleted: json['deleted'] as bool? ?? false,
        genealogyKnowledge: json['genealogyKnowledge'] as String? ?? 'UNKNOWN',
        relationship: json['relationship'] as String? ?? 'RELATIVE',
      );
}

class IndividualInbreeding {
  const IndividualInbreeding({
    required this.status,
    required this.coefficient,
    required this.minimumKnownCoefficient,
    required this.isExact,
    required this.riskLevel,
    required this.warnings,
  });

  final String status;
  final String? coefficient;
  final String? minimumKnownCoefficient;
  final bool isExact;
  final String riskLevel;
  final List<String> warnings;

  factory IndividualInbreeding.fromJson(Map<String, dynamic> json) =>
      IndividualInbreeding(
        status: json['status'] as String? ?? 'NO_CALCULABLE',
        coefficient: json['coefficient']?.toString(),
        minimumKnownCoefficient: json['minimumKnownCoefficient']?.toString(),
        isExact: json['isExact'] as bool? ?? false,
        riskLevel: json['riskLevel'] as String? ?? 'NO_CALCULABLE',
        warnings: (json['warnings'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
      );
}

class Pedigree {
  const Pedigree({
    this.father,
    this.mother,
    required this.ancestors,
    required this.descendants,
    required this.integrity,
    required this.integrityIssues,
    required this.links,
    this.individualInbreeding,
    this.local,
  });

  final PedigreeAnimal? father;
  final PedigreeAnimal? mother;
  final List<PedigreeAnimal> ancestors;
  final List<PedigreeAnimal> descendants;
  final String integrity;
  final List<String> integrityIssues;
  final List<PedigreeLink> links;
  final IndividualInbreeding? individualInbreeding;
  final LocalGenealogy? local;

  int? versionFor(String role, {String? childUuid}) {
    for (final link in links) {
      if (link.role == role &&
          (childUuid == null || link.childUuid == childUuid)) {
        return link.version;
      }
    }
    return null;
  }

  factory Pedigree.fromJson(Map<String, dynamic> json) {
    PedigreeAnimal? node(dynamic raw) => raw is Map<String, dynamic>
        ? PedigreeAnimal.fromJson(raw)
        : raw is Map
            ? PedigreeAnimal.fromJson(Map<String, dynamic>.from(raw))
            : null;
    List<PedigreeAnimal> nodes(dynamic raw) => raw is List
        ? raw.map(node).whereType<PedigreeAnimal>().toList(growable: false)
        : const [];
    return Pedigree(
      father: node(json['father']),
      mother: node(json['mother']),
      ancestors: nodes(json['ancestors']),
      descendants: nodes(json['descendants']),
      integrity: json['integrity'] as String? ?? 'VALID',
      integrityIssues: (json['integrityIssues'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      links: (json['links'] as List? ?? const [])
          .map((item) =>
              PedigreeLink.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      individualInbreeding: json['individualInbreeding'] is Map
          ? IndividualInbreeding.fromJson(
              Map<String, dynamic>.from(json['individualInbreeding'] as Map))
          : null,
    );
  }
}

class PedigreeLink {
  const PedigreeLink({
    required this.role,
    required this.version,
    this.childUuid,
  });
  final String role;
  final int version;
  final String? childUuid;
  factory PedigreeLink.fromJson(Map<String, dynamic> json) => PedigreeLink(
        role: json['role'] as String,
        version: (json['version'] as num).toInt(),
        childUuid: json['child_uuid'] as String?,
      );
}

class KinshipAncestor {
  const KinshipAncestor({
    required this.uuid,
    required this.n1,
    required this.n2,
    required this.contribution,
    this.name = '',
  });
  final String uuid;
  final int n1;
  final int n2;
  final String contribution;
  final String name;

  factory KinshipAncestor.fromJson(Map<String, dynamic> json) =>
      KinshipAncestor(
        uuid: json['uuid'] as String,
        n1: (json['n1'] as num).toInt(),
        n2: (json['n2'] as num).toInt(),
        contribution: json['contribution'].toString(),
        name: json['name'] as String? ?? '',
      );
}

class KinshipEvaluation {
  const KinshipEvaluation({
    required this.status,
    required this.relationshipCoefficient,
    required this.expectedInbreeding,
    required this.riskLevel,
    required this.commonAncestors,
    required this.reason,
    this.minimumKnownInbreeding,
    this.isExact = false,
    this.relationshipType = 'UNKNOWN',
    this.warnings = const [],
    this.unknownBranches = const [],
    this.independenceAssumptionApplied = false,
    this.declaredFounders = const [],
    this.local,
  });
  final String status;
  final String? relationshipCoefficient;
  final String? expectedInbreeding;
  final String riskLevel;
  final List<KinshipAncestor> commonAncestors;
  final String? reason;
  final String? minimumKnownInbreeding;
  final bool isExact;
  final String relationshipType;
  final List<String> warnings;
  final List<String> unknownBranches;
  final bool independenceAssumptionApplied;
  final List<String> declaredFounders;
  final LocalGenealogy? local;
  bool get calculable => status == 'CALCULABLE';
  bool get hasKnownMinimum => minimumKnownInbreeding != null;

  factory KinshipEvaluation.fromJson(Map<String, dynamic> json,
          {LocalGenealogy? local}) =>
      KinshipEvaluation(
        local: local,
        status: json['status'] as String,
        relationshipCoefficient: json['relationshipCoefficient']?.toString(),
        expectedInbreeding: json['expectedInbreeding']?.toString(),
        riskLevel: json['riskLevel'] as String? ?? 'NO_CALCULABLE',
        commonAncestors: (json['commonAncestors'] as List? ?? const [])
            .map((item) => KinshipAncestor.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
        reason: json['reason'] as String?,
        minimumKnownInbreeding: json['minimumKnownInbreeding']?.toString(),
        isExact: json['isExact'] as bool? ?? false,
        relationshipType: json['relationshipType'] as String? ?? 'UNKNOWN',
        warnings: (json['warnings'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
        unknownBranches: (json['unknownBranches'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
        independenceAssumptionApplied:
            json['independenceAssumptionApplied'] as bool? ?? false,
        declaredFounders: (json['declaredFounders'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
      );
}

class ReproductiveEvent {
  const ReproductiveEvent({
    required this.uuid,
    required this.maleUuid,
    required this.maleName,
    required this.femaleUuid,
    required this.femaleName,
    required this.matingDate,
    required this.estimatedBirthDate,
    required this.notes,
    required this.version,
    required this.calendarState,
    required this.daysRemaining,
    required this.kinship,
    this.local,
  });
  final String uuid;
  final String maleUuid;
  final String maleName;
  final String femaleUuid;
  final String femaleName;
  final String matingDate;
  final String estimatedBirthDate;
  final String notes;
  final int version;
  final String calendarState;
  final int daysRemaining;
  final KinshipEvaluation kinship;
  final LocalReproductiveRecord? local;

  factory ReproductiveEvent.fromJson(Map<String, dynamic> json) =>
      ReproductiveEvent(
        uuid: json['uuid'] as String,
        maleUuid: json['male_uuid'] as String,
        maleName: json['male_name'] as String? ?? 'Macho',
        femaleUuid: json['female_uuid'] as String,
        femaleName: json['female_name'] as String? ?? 'Hembra',
        matingDate: json['mating_date'] as String,
        estimatedBirthDate: json['estimated_birth_date'] as String,
        notes: json['notes'] as String? ?? '',
        version: (json['version'] as num).toInt(),
        calendarState: json['calendar_state'] as String,
        daysRemaining: (json['days_remaining'] as num).toInt(),
        kinship: KinshipEvaluation.fromJson(
          Map<String, dynamic>.from(json['kinship_evaluation'] as Map),
        ),
      );
}
