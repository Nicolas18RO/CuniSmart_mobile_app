"""Coeficiente de parentesco y consanguinidad esperada.

DECISIÓN TÉCNICA APROBADA — GATE R3.0

Para cada ancestro común A, con caminos independientes (solo coinciden en A):

    (1/2)^(n1 + n2) * (1 + F_A)

La suma es el coeficiente de relación. La consanguinidad esperada del cruce
es ese coeficiente dividido entre 2. Un ancestro más lejano no se suma si
el camino ya pasa por un ancestro común más cercano.

Umbrales sobre la consanguinidad esperada: 6.25 % y 12.5 %.
"""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction


PREVENTIVE_THRESHOLD = Fraction(1, 16)
HIGH_THRESHOLD = Fraction(1, 8)
INSUFFICIENT = "INFORMACIÓN_GENEALÓGICA_INSUFICIENTE"
LIMIT = "LÍMITE_TÉCNICO_DE_GENEALOGÍA"
MAX_DEPTH = 128
MAX_PATHS = 4096
MAX_PATH_PAIRS = 1_000_000


class CalculationLimit(Exception):
    pass


@dataclass(frozen=True)
class Animal:
    uuid: str
    father: str | None
    mother: str | None
    knowledge: str = "UNKNOWN"
    name: str = ""
    sex: str = ""


@dataclass(frozen=True)
class CommonAncestor:
    uuid: str
    n1: int
    n2: int
    contribution: Fraction
    name: str = ""


@dataclass(frozen=True)
class KinshipResult:
    status: str
    relationship: Fraction | None
    expected_inbreeding: Fraction | None
    risk_level: str
    common_ancestors: list[CommonAncestor]
    reason: str | None
    relationship_type: str = "UNKNOWN"
    minimum_known_inbreeding: Fraction | None = None
    is_exact: bool = False
    warnings: tuple[str, ...] = ()
    unknown_branches: tuple[str, ...] = ()
    independence_assumption_applied: bool = False
    declared_founders: tuple[str, ...] = ()

    def to_payload(self) -> dict:
        return {
            "status": self.status,
            "relationshipCoefficient": _decimal(self.relationship),
            "expectedInbreeding": _decimal(self.expected_inbreeding),
            "minimumKnownInbreeding": _decimal(self.minimum_known_inbreeding),
            "isExact": self.is_exact,
            "relationshipType": self.relationship_type,
            "riskLevel": self.risk_level,
            "commonAncestors": [
                {
                    "uuid": item.uuid,
                    "n1": item.n1,
                    "n2": item.n2,
                    "contribution": _decimal(item.contribution),
                    "name": item.name,
                }
                for item in self.common_ancestors
            ],
            "reason": self.reason,
            "warnings": list(self.warnings),
            "unknownBranches": list(self.unknown_branches),
            "independenceAssumptionApplied": self.independence_assumption_applied,
            "declaredFounders": list(self.declared_founders),
        }


def risk_level_for(inbreeding: Fraction) -> str:
    if inbreeding >= HIGH_THRESHOLD:
        return "ALTO"
    if inbreeding >= PREVENTIVE_THRESHOLD:
        return "PREVENTIVO"
    return "SIN_ADVERTENCIA"


def evaluate(a: str, b: str, animals: dict[str, Animal]) -> KinshipResult:
    engine = _Engine(animals)
    founders = tuple(engine.declared_founders(a, b))
    complete = engine.is_complete(a) and engine.is_complete(b)
    try:
        relationship, ancestors = engine.relationship(a, b)
    except CalculationLimit:
        return KinshipResult(
            status="NO_CALCULABLE",
            relationship=None,
            expected_inbreeding=None,
            risk_level="NO_CALCULABLE",
            common_ancestors=[],
            reason=LIMIT,
            relationship_type=engine.relationship_type(a, b),
            warnings=(LIMIT,),
            unknown_branches=tuple(engine.unknown_branches(a, b)),
            independence_assumption_applied=bool(founders),
            declared_founders=founders,
        )

    relationship_type = engine.relationship_type(a, b)
    unknown = tuple(engine.unknown_branches(a, b))
    if engine.has_inconsistent_state(a, b):
        return KinshipResult(
            status="NO_CALCULABLE",
            relationship=None,
            expected_inbreeding=None,
            risk_level="NO_CALCULABLE",
            common_ancestors=[],
            reason=INSUFFICIENT,
            relationship_type=relationship_type,
            is_exact=False,
            warnings=("INCONSISTENT_GENEALOGY",),
            unknown_branches=unknown,
            independence_assumption_applied=bool(founders),
            declared_founders=founders,
        )
    if not complete:
        if relationship == 0:
            return KinshipResult(
                status="NO_CALCULABLE",
                relationship=None,
                expected_inbreeding=None,
                risk_level="NO_CALCULABLE",
                common_ancestors=[],
                reason=LIMIT if engine.limit_reached else INSUFFICIENT,
                relationship_type=relationship_type,
                is_exact=False,
                warnings=("INCOMPLETE_GENEALOGY",),
                unknown_branches=unknown,
                declared_founders=founders,
            )
        minimum = relationship / 2
        return KinshipResult(
            status="PARTIAL",
            relationship=relationship,
            expected_inbreeding=None,
            minimum_known_inbreeding=minimum,
            is_exact=False,
            risk_level=risk_level_for(minimum),
            common_ancestors=ancestors,
            reason=INSUFFICIENT,
            relationship_type=relationship_type,
            warnings=("INCOMPLETE_GENEALOGY", "MINIMUM_KNOWN_ONLY"),
            unknown_branches=unknown,
            independence_assumption_applied=bool(founders),
            declared_founders=founders,
        )

    expected = relationship / 2
    return KinshipResult(
        status="CALCULABLE",
        relationship=relationship,
        expected_inbreeding=expected,
        risk_level=risk_level_for(expected),
        common_ancestors=ancestors,
        reason=None,
        relationship_type=relationship_type,
        minimum_known_inbreeding=expected,
        is_exact=True,
        warnings=(),
        unknown_branches=(),
        independence_assumption_applied=bool(founders),
        declared_founders=founders,
    )


class _Engine:
    def __init__(self, animals: dict[str, Animal]):
        self.animals = animals
        self._complete: dict[str, bool] = {}
        self._inbreeding: dict[str, Fraction] = {}
        self.limit_reached = False

    def is_complete(self, uuid: str, stack: frozenset[str] | None = None) -> bool:
        if stack and len(stack) >= MAX_DEPTH:
            self.limit_reached = True
            return False
        if uuid in self._complete and not stack:
            return self._complete[uuid]
        if uuid not in self.animals:
            return False
        if stack and uuid in stack:
            return False
        animal = self.animals[uuid]
        if animal.knowledge not in ("FOUNDER", "RECORDED"):
            return False
        parents = [animal.father, animal.mother]
        known = [parent for parent in parents if parent]
        if animal.knowledge == "FOUNDER":
            return not known
        if len(known) == 1:
            self._complete[uuid] = False
            return False
        if len(known) == 0:
            return False
        next_stack = (stack or frozenset()) | {uuid}
        complete = all(self.is_complete(parent, next_stack) for parent in known)
        if not stack:
            self._complete[uuid] = complete
        return complete

    def inbreeding(self, uuid: str) -> Fraction:
        cached = self._inbreeding.get(uuid)
        if cached is not None:
            return cached
        animal = self.animals[uuid]
        if not animal.father or not animal.mother:
            self._inbreeding[uuid] = Fraction(0)
            return Fraction(0)
        relationship, _ancestors = self.relationship(animal.father, animal.mother)
        value = relationship / 2
        self._inbreeding[uuid] = value
        return value

    def relationship(self, left: str, right: str):
        left_paths = self._paths(left)
        right_paths = self._paths(right)
        if len(left_paths) * len(right_paths) > MAX_PATH_PAIRS:
            raise CalculationLimit()
        total = Fraction(0)
        found: list[CommonAncestor] = []
        for ancestor, n1, nodes1 in left_paths:
            for other, n2, nodes2 in right_paths:
                if ancestor != other:
                    continue
                if nodes1 & nodes2 != {ancestor}:
                    continue
                contribution = Fraction(1, 2) ** (n1 + n2) * (1 + self.inbreeding(ancestor))
                total += contribution
                found.append(
                    CommonAncestor(
                        uuid=ancestor,
                        n1=n1,
                        n2=n2,
                        contribution=contribution,
                        name=self.animals.get(ancestor, Animal(ancestor, None, None)).name,
                    )
                )
        found.sort(key=lambda item: (item.uuid, item.n1, item.n2))
        return total, found

    def relationship_type(self, left: str, right: str) -> str:
        if left == right:
            return "SAME_ANIMAL"
        one = self.animals.get(left)
        two = self.animals.get(right)
        if one is None or two is None:
            return "UNKNOWN"
        if left == two.father:
            return _direct_relationship("FATHER", two.sex)
        if left == two.mother:
            return _direct_relationship("MOTHER", two.sex)
        if right == one.father:
            return _direct_relationship("FATHER", one.sex)
        if right == one.mother:
            return _direct_relationship("MOTHER", one.sex)
        shared = {one.father, one.mother} & {two.father, two.mother}
        shared.discard(None)
        if len(shared) == 2:
            return "FULL_SIBLINGS"
        if len(shared) == 1:
            return "HALF_SIBLINGS"
        if self._is_uncle_pair(left, right):
            return "UNCLE_AUNT_NEPHEW_NIECE"
        if self._are_first_cousins(left, right):
            return "FIRST_COUSINS"
        left_depth = self._ancestor_depth(left, right)
        right_depth = self._ancestor_depth(right, left)
        depth = left_depth if left_depth is not None else right_depth
        if depth == 2:
            return "GRANDPARENT_GRANDCHILD"
        if depth is not None:
            return "ANCESTOR_DESCENDANT"
        return "UNRELATED" if self.is_complete(left) and self.is_complete(right) else "UNKNOWN"

    def _parents(self, uuid: str) -> set[str]:
        animal = self.animals.get(uuid)
        if animal is None:
            return set()
        return {item for item in (animal.father, animal.mother) if item}

    def _are_siblings(self, left: str, right: str) -> bool:
        return bool(self._parents(left) & self._parents(right))

    def _is_uncle_pair(self, left: str, right: str) -> bool:
        return any(self._are_siblings(left, parent) for parent in self._parents(right)) or any(
            self._are_siblings(right, parent) for parent in self._parents(left)
        )

    def _are_first_cousins(self, left: str, right: str) -> bool:
        return any(
            self._are_siblings(one, other)
            for one in self._parents(left)
            for other in self._parents(right)
        )

    def declared_founders(self, *starts: str) -> list[str]:
        pending = list(starts)
        visited: set[str] = set()
        found: set[str] = set()
        while pending:
            current = pending.pop()
            if current in visited:
                continue
            visited.add(current)
            animal = self.animals.get(current)
            if animal is None:
                continue
            if animal.knowledge == "FOUNDER" and not animal.father and not animal.mother:
                found.add(animal.name or animal.uuid)
            pending.extend(item for item in (animal.father, animal.mother) if item)
        return sorted(found)

    def _ancestor_depth(self, descendant: str, ancestor: str) -> int | None:
        depths = [length for current, length, _nodes in self._paths(descendant)
                  if current == ancestor]
        return min(depths) if depths else None

    def unknown_branches(self, *starts: str) -> list[str]:
        pending = list(starts)
        visited: set[str] = set()
        unknown: set[str] = set()
        while pending:
            current = pending.pop()
            if current in visited:
                continue
            visited.add(current)
            animal = self.animals.get(current)
            if animal is None:
                unknown.add(current)
                continue
            parents = [item for item in (animal.father, animal.mother) if item]
            if animal.knowledge == "UNKNOWN":
                unknown.add(current)
            elif animal.knowledge == "RECORDED" and len(parents) != 2:
                unknown.add(current)
            elif animal.knowledge not in ("FOUNDER", "RECORDED"):
                unknown.add(current)
            pending.extend(parents)
        return sorted(unknown)

    def has_inconsistent_state(self, *starts: str) -> bool:
        pending = list(starts)
        visited: set[str] = set()
        while pending:
            current = pending.pop()
            if current in visited:
                continue
            visited.add(current)
            animal = self.animals.get(current)
            if animal is None:
                continue
            parents = [item for item in (animal.father, animal.mother) if item]
            if animal.knowledge == "FOUNDER" and parents:
                return True
            if animal.knowledge == "RECORDED" and len(parents) != 2:
                return True
            pending.extend(parents)
        return False

    def _paths(self, start: str):
        results: list[tuple[str, int, frozenset[str]]] = []

        def walk(current: str, length: int, nodes: frozenset[str]) -> None:
            if len(results) >= MAX_PATHS:
                raise CalculationLimit()
            results.append((current, length, nodes))
            animal = self.animals.get(current)
            if animal is None:
                return
            for parent in (animal.father, animal.mother):
                if parent and parent not in nodes:
                    walk(parent, length + 1, nodes | {parent})

        walk(start, 0, frozenset({start}))
        return results


def _decimal(value: Fraction | None) -> str | None:
    if value is None:
        return None
    sign = "-" if value < 0 else ""
    numerator = abs(value.numerator)
    denominator = value.denominator
    whole, rem = divmod(numerator, denominator)
    if rem == 0:
        return f"{sign}{whole}"
    digits: list[str] = []
    seen = set()
    while rem:
        if rem in seen:
            raise ValueError("Non-terminating decimal")
        seen.add(rem)
        rem *= 10
        digit, rem = divmod(rem, denominator)
        digits.append(str(digit))
    text = "".join(digits).rstrip("0")
    return f"{sign}{whole}.{text}"


def _direct_relationship(parent_role: str, child_sex: str) -> str:
    child = "SON" if child_sex == "male" else "DAUGHTER" if child_sex == "female" else "CHILD"
    return f"{parent_role}_{child}"
