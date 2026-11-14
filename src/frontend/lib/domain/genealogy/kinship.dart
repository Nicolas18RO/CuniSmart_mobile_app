import 'fraction.dart';

/// Relationship and expected inbreeding.
///
/// Approved prototype formula: independent common-ancestor paths
/// `(1/2)^(n1 + n2) * (1 + F_A)`, then expected inbreeding is half of that.
/// Thresholds apply to expected inbreeding: 6.25% and 12.5%.
class KinshipAnimal {
  const KinshipAnimal({
    required this.uuid,
    this.father,
    this.mother,
    this.knowledge = 'UNKNOWN',
    this.name = '',
    this.sex = '',
  });

  final String uuid;
  final String? father;
  final String? mother;
  final String knowledge;
  final String name;
  final String sex;
}

class CommonAncestorContribution {
  const CommonAncestorContribution({
    required this.uuid,
    required this.n1,
    required this.n2,
    required this.contribution,
    this.name = '',
  });

  final String uuid;
  final int n1;
  final int n2;
  final Fraction contribution;
  final String name;
}

class KinshipResult {
  const KinshipResult({
    required this.status,
    required this.relationship,
    required this.expectedInbreeding,
    required this.riskLevel,
    required this.commonAncestors,
    required this.reason,
    this.relationshipType = 'UNKNOWN',
    this.minimumKnownInbreeding,
    this.isExact = false,
    this.warnings = const [],
    this.unknownBranches = const [],
    this.independenceAssumptionApplied = false,
    this.declaredFounders = const [],
  });

  final String status;
  final Fraction? relationship;
  final Fraction? expectedInbreeding;
  final String riskLevel;
  final List<CommonAncestorContribution> commonAncestors;
  final String? reason;
  final String relationshipType;
  final Fraction? minimumKnownInbreeding;
  final bool isExact;
  final List<String> warnings;
  final List<String> unknownBranches;
  final bool independenceAssumptionApplied;
  final List<String> declaredFounders;

  Map<String, Object?> toPayload() {
    return {
      'status': status,
      'relationshipCoefficient': relationship?.toDecimalString(),
      'expectedInbreeding': expectedInbreeding?.toDecimalString(),
      'minimumKnownInbreeding': minimumKnownInbreeding?.toDecimalString(),
      'isExact': isExact,
      'relationshipType': relationshipType,
      'riskLevel': riskLevel,
      'commonAncestors': [
        for (final item in commonAncestors)
          {
            'uuid': item.uuid,
            'n1': item.n1,
            'n2': item.n2,
            'contribution': item.contribution.toDecimalString(),
            'name': item.name,
          },
      ],
      'reason': reason,
      'warnings': warnings,
      'unknownBranches': unknownBranches,
      'independenceAssumptionApplied': independenceAssumptionApplied,
      'declaredFounders': declaredFounders,
    };
  }
}

const preventiveThreshold = Fraction(1, 16);
const highThreshold = Fraction(1, 8);
const insufficientGenealogyReason = 'INFORMACIÓN_GENEALÓGICA_INSUFICIENTE';
const genealogyLimitReason = 'LÍMITE_TÉCNICO_DE_GENEALOGÍA';

class _CalculationLimit implements Exception {}

String riskLevelFor(Fraction inbreeding) {
  if (inbreeding >= highThreshold) return 'ALTO';
  if (inbreeding >= preventiveThreshold) return 'PREVENTIVO';
  return 'SIN_ADVERTENCIA';
}

KinshipResult evaluateKinship(
  String left,
  String right,
  Map<String, KinshipAnimal> herd,
) {
  final engine = _Engine(herd);
  final complete = engine.isComplete(left) && engine.isComplete(right);
  late _Pair pair;
  try {
    pair = engine.relationship(left, right);
  } on _CalculationLimit {
    return KinshipResult(
        status: 'NO_CALCULABLE',
        relationship: null,
        expectedInbreeding: null,
        riskLevel: 'NO_CALCULABLE',
        commonAncestors: [],
        reason: genealogyLimitReason,
        relationshipType: engine.relationshipType(left, right),
        warnings: const [genealogyLimitReason],
        unknownBranches: engine.unknownBranches(left, right));
  }
  final relationshipType = engine.relationshipType(left, right);
  final unknown = engine.unknownBranches(left, right);
  final founders = engine.declaredFounders(left, right);
  if (engine.hasInconsistentState(left, right)) {
    return KinshipResult(
      status: 'NO_CALCULABLE',
      relationship: null,
      expectedInbreeding: null,
      riskLevel: 'NO_CALCULABLE',
      commonAncestors: const [],
      reason: insufficientGenealogyReason,
      relationshipType: relationshipType,
      warnings: const ['INCONSISTENT_GENEALOGY'],
      unknownBranches: unknown,
      independenceAssumptionApplied: founders.isNotEmpty,
      declaredFounders: founders,
    );
  }
  if (!complete) {
    if (pair.total == const Fraction(0, 1)) {
      return KinshipResult(
        status: 'NO_CALCULABLE',
        relationship: null,
        expectedInbreeding: null,
        riskLevel: 'NO_CALCULABLE',
        commonAncestors: const [],
        reason: engine.limitReached
            ? genealogyLimitReason
            : insufficientGenealogyReason,
        relationshipType: relationshipType,
        warnings: const ['INCOMPLETE_GENEALOGY'],
        unknownBranches: unknown,
        independenceAssumptionApplied: founders.isNotEmpty,
        declaredFounders: founders,
      );
    }
    final minimum = pair.total / 2;
    return KinshipResult(
      status: 'PARTIAL',
      relationship: pair.total,
      expectedInbreeding: null,
      minimumKnownInbreeding: minimum,
      isExact: false,
      riskLevel: riskLevelFor(minimum),
      commonAncestors: pair.ancestors,
      reason: insufficientGenealogyReason,
      relationshipType: relationshipType,
      warnings: const ['INCOMPLETE_GENEALOGY', 'MINIMUM_KNOWN_ONLY'],
      unknownBranches: unknown,
      independenceAssumptionApplied: founders.isNotEmpty,
      declaredFounders: founders,
    );
  }
  final expected = pair.total / 2;
  return KinshipResult(
    status: 'CALCULABLE',
    relationship: pair.total,
    expectedInbreeding: expected,
    riskLevel: riskLevelFor(expected),
    commonAncestors: pair.ancestors,
    reason: null,
    relationshipType: relationshipType,
    minimumKnownInbreeding: expected,
    isExact: true,
    independenceAssumptionApplied: founders.isNotEmpty,
    declaredFounders: founders,
  );
}

class _Path {
  const _Path(this.ancestor, this.length, this.nodes);

  final String ancestor;
  final int length;
  final Set<String> nodes;
}

class _Pair {
  const _Pair(this.total, this.ancestors);

  final Fraction total;
  final List<CommonAncestorContribution> ancestors;
}

class _Engine {
  _Engine(this.herd);

  final Map<String, KinshipAnimal> herd;
  final Map<String, bool> _complete = {};
  final Map<String, Fraction> _inbreeding = {};
  bool limitReached = false;

  bool isComplete(String uuid, [Set<String>? stack]) {
    if (stack != null && stack.length >= 128) {
      limitReached = true;
      return false;
    }
    if (stack == null && _complete.containsKey(uuid)) {
      return _complete[uuid]!;
    }
    final animal = herd[uuid];
    if (animal == null) return false;
    if (animal.knowledge != 'FOUNDER' && animal.knowledge != 'RECORDED') {
      return false;
    }
    if (stack != null && stack.contains(uuid)) return false;
    final known = [animal.father, animal.mother].whereType<String>().toList();
    if (animal.knowledge == 'FOUNDER') return known.isEmpty;
    if (known.length == 1) {
      _complete[uuid] = false;
      return false;
    }
    if (known.isEmpty) {
      return false;
    }
    final next = {...?stack, uuid};
    final complete = known.every((parent) => isComplete(parent, next));
    if (stack == null) _complete[uuid] = complete;
    return complete;
  }

  Fraction inbreedingOf(String uuid) {
    final cached = _inbreeding[uuid];
    if (cached != null) return cached;
    final animal = herd[uuid];
    if (animal == null || animal.father == null || animal.mother == null) {
      const base = Fraction(0, 1);
      _inbreeding[uuid] = base;
      return base;
    }
    final value = relationship(animal.father!, animal.mother!).total / 2;
    _inbreeding[uuid] = value;
    return value;
  }

  _Pair relationship(String left, String right) {
    final leftPaths = _paths(left);
    final rightPaths = _paths(right);
    if (leftPaths.length * rightPaths.length > 1000000) {
      throw _CalculationLimit();
    }
    var total = const Fraction(0, 1);
    final found = <CommonAncestorContribution>[];
    for (final one in leftPaths) {
      for (final other in rightPaths) {
        if (one.ancestor != other.ancestor) continue;
        final shared = one.nodes.intersection(other.nodes);
        if (shared.length != 1 || !shared.contains(one.ancestor)) continue;
        final contribution =
            const Fraction(1, 2).pow(one.length + other.length) *
                (const Fraction(1, 1) + inbreedingOf(one.ancestor));
        total += contribution;
        found.add(
          CommonAncestorContribution(
            uuid: one.ancestor,
            n1: one.length,
            n2: other.length,
            contribution: contribution,
            name: herd[one.ancestor]?.name ?? '',
          ),
        );
      }
    }
    found.sort((a, b) {
      final byUuid = a.uuid.compareTo(b.uuid);
      if (byUuid != 0) return byUuid;
      final byN1 = a.n1.compareTo(b.n1);
      if (byN1 != 0) return byN1;
      return a.n2.compareTo(b.n2);
    });
    return _Pair(total, found);
  }

  String relationshipType(String left, String right) {
    if (left == right) return 'SAME_ANIMAL';
    final leftAnimal = herd[left];
    final rightAnimal = herd[right];
    if (rightAnimal?.father == left) {
      return _directRelationship('FATHER', rightAnimal?.sex ?? '');
    }
    if (rightAnimal?.mother == left) {
      return _directRelationship('MOTHER', rightAnimal?.sex ?? '');
    }
    if (leftAnimal?.father == right) {
      return _directRelationship('FATHER', leftAnimal?.sex ?? '');
    }
    if (leftAnimal?.mother == right) {
      return _directRelationship('MOTHER', leftAnimal?.sex ?? '');
    }
    final leftParents =
        [leftAnimal?.father, leftAnimal?.mother].whereType<String>().toSet();
    final rightParents =
        [rightAnimal?.father, rightAnimal?.mother].whereType<String>().toSet();
    final shared = leftParents.intersection(rightParents);
    if (shared.length == 2) return 'FULL_SIBLINGS';
    if (shared.length == 1) return 'HALF_SIBLINGS';
    if (_isUnclePair(left, right)) return 'UNCLE_AUNT_NEPHEW_NIECE';
    if (_areFirstCousins(left, right)) return 'FIRST_COUSINS';
    final leftDepth = _ancestorDepth(left, right);
    final rightDepth = _ancestorDepth(right, left);
    final depth = leftDepth ?? rightDepth;
    if (depth == 2) return 'GRANDPARENT_GRANDCHILD';
    if (depth != null) return 'ANCESTOR_DESCENDANT';
    return isComplete(left) && isComplete(right) ? 'UNRELATED' : 'UNKNOWN';
  }

  Set<String> _parents(String uuid) {
    final animal = herd[uuid];
    if (animal == null) return const {};
    return [animal.father, animal.mother].whereType<String>().toSet();
  }

  bool _areSiblings(String left, String right) =>
      _parents(left).intersection(_parents(right)).isNotEmpty;

  bool _isUnclePair(String left, String right) =>
      _parents(right).any((parent) => _areSiblings(left, parent)) ||
      _parents(left).any((parent) => _areSiblings(right, parent));

  bool _areFirstCousins(String left, String right) => _parents(left).any(
        (one) => _parents(right).any((other) => _areSiblings(one, other)),
      );

  List<String> declaredFounders(String left, String right) {
    final pending = <String>[left, right];
    final visited = <String>{};
    final found = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      final animal = herd[current];
      if (animal == null) continue;
      if (animal.knowledge == 'FOUNDER' &&
          animal.father == null &&
          animal.mother == null) {
        found.add(animal.name.isEmpty ? animal.uuid : animal.name);
      }
      pending.addAll([animal.father, animal.mother].whereType<String>());
    }
    final result = found.toList()..sort();
    return result;
  }

  int? _ancestorDepth(String descendant, String ancestor) {
    final matches = _paths(descendant)
        .where((path) => path.ancestor == ancestor)
        .map((path) => path.length)
        .toList();
    if (matches.isEmpty) return null;
    matches.sort();
    return matches.first;
  }

  List<String> unknownBranches(String left, String right) {
    final pending = <String>[left, right];
    final visited = <String>{};
    final unknown = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      final animal = herd[current];
      if (animal == null) {
        unknown.add(current);
        continue;
      }
      final parents =
          [animal.father, animal.mother].whereType<String>().toList();
      if (animal.knowledge == 'UNKNOWN' ||
          (animal.knowledge == 'RECORDED' && parents.length != 2) ||
          (animal.knowledge != 'FOUNDER' && animal.knowledge != 'RECORDED')) {
        unknown.add(current);
      }
      pending.addAll(parents);
    }
    final result = unknown.toList()..sort();
    return result;
  }

  bool hasInconsistentState(String left, String right) {
    final pending = <String>[left, right];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      final animal = herd[current];
      if (animal == null) continue;
      final parents =
          [animal.father, animal.mother].whereType<String>().toList();
      if (animal.knowledge == 'FOUNDER' && parents.isNotEmpty) return true;
      if (animal.knowledge == 'RECORDED' && parents.length != 2) return true;
      pending.addAll(parents);
    }
    return false;
  }

  List<_Path> _paths(String start) {
    final results = <_Path>[];

    void walk(String current, int length, Set<String> nodes) {
      if (results.length >= 4096) throw _CalculationLimit();
      results.add(_Path(current, length, nodes));
      final animal = herd[current];
      if (animal == null) return;
      for (final parent in [animal.father, animal.mother]) {
        if (parent != null && !nodes.contains(parent)) {
          walk(parent, length + 1, {...nodes, parent});
        }
      }
    }

    walk(start, 0, {start});
    return results;
  }
}

String _directRelationship(String parentRole, String childSex) {
  final child = childSex == 'male'
      ? 'SON'
      : childSex == 'female'
          ? 'DAUGHTER'
          : 'CHILD';
  return '${parentRole}_$child';
}
