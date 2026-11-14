"""Reglas de parentesco de R3. El UUID del conejo sigue siendo la identidad."""

from collections import deque
from functools import wraps
from django.utils import timezone
from rest_framework.exceptions import NotFound, ValidationError

from .exceptions import VersionConflict
from .models import ParentLink, Rabbit
from .genealogy_transactions import owner_write, record_knowledge


def graph_mutation(function):
    @wraps(function)
    def locked(*, child, **kwargs):
        owner_id = child.user_id
        with owner_write(owner_id):
            child.refresh_from_db()
            if child.user_id != owner_id or child.deleted_at is not None:
                raise NotFound()
            parent = kwargs.get("parent")
            if parent is not None:
                parent.refresh_from_db()
            version = kwargs.get("version")
            if version is not None and (
                type(version) is not int or not 1 <= version <= 2147483647
            ):
                raise ValidationError("La versión no es válida.")
            return function(child=child, **kwargs)
    return locked


def snapshot(link: ParentLink) -> dict:
    return {
        "child_uuid": str(link.child.uuid),
        "parent_uuid": str(link.parent.uuid),
        "role": link.role,
        "version": link.version,
        "deleted_at": link.deleted_at.isoformat() if link.deleted_at else None,
    }


def public_link(link: ParentLink) -> dict:
    return snapshot(link)


@graph_mutation
def assign_or_update(*, child: Rabbit, parent: Rabbit, role: str, version):
    if role not in (ParentLink.Role.FATHER, ParentLink.Role.MOTHER):
        raise ValidationError("El rol de progenitor no es válido.")
    if child.pk == parent.pk:
        raise ValidationError("Un animal no puede ser su propio progenitor.")
    if child.user_id != parent.user_id:
        raise NotFound()
    if child.deleted_at is not None or parent.deleted_at is not None:
        raise NotFound()
    if child.genealogy_knowledge == Rabbit.GenealogyKnowledge.FOUNDER:
        raise ValidationError("Declare UNKNOWN antes de asignar padres a un fundador.")

    links = list(
        ParentLink.objects.filter(
            deleted_at__isnull=True,
            child__user_id=child.user_id,
        ).select_related("child", "parent")
    )
    if any(link.parent.user_id != child.user_id for link in links):
        raise ValidationError("Existen relaciones genealógicas inconsistentes.")
    other = (
        ParentLink.Role.MOTHER
        if role == ParentLink.Role.FATHER
        else ParentLink.Role.FATHER
    )
    for link in links:
        if (
            link.child_id == child.id
            and link.role == other
            and link.parent_id == parent.id
        ):
            raise ValidationError(
                "El padre y la madre no pueden ser el mismo animal."
            )

    if role == ParentLink.Role.FATHER and parent.sex != Rabbit.Sex.MALE:
        raise ValidationError("El padre debe ser macho.")
    if role == ParentLink.Role.MOTHER and parent.sex != Rabbit.Sex.FEMALE:
        raise ValidationError("La madre debe ser hembra.")

    cycle = _cycle(child.id, parent.id, links)
    if cycle == "direct":
        raise ValidationError("La relación forma un ciclo genealógico directo.")
    if cycle == "indirect":
        raise ValidationError("La relación forma un ciclo genealógico.")

    current = next(
        (
            link
            for link in links
            if link.child_id == child.id and link.role == role
        ),
        None,
    )
    if current is None:
        latest = ParentLink.objects.filter(child=child, role=role).order_by("-version").first()
        if version is not None:
            raise VersionConflict(current={}, detail="La relación ya no está activa.")
        creation_version = latest.version + 1 if latest else 1
        current = ParentLink.objects.create(
            child=child, parent=parent, role=role,
            version=creation_version,
            creation_version=creation_version,
        )
        _refresh_knowledge(child)
        return current
    if version is None or version != current.version:
        raise VersionConflict(
            current=snapshot(current),
            detail="El parentesco fue modificado en otro lugar.",
        )
    current.parent = parent
    current.version = current.version + 1
    current.save(update_fields=["parent", "version", "updated_at"])
    current.refresh_from_db()
    _refresh_knowledge(child)
    return current


@graph_mutation
def clear_parent(*, child: Rabbit, role: str, version):
    if role not in (ParentLink.Role.FATHER, ParentLink.Role.MOTHER):
        raise ValidationError("El rol de progenitor no es válido.")
    current = (
        ParentLink.objects.filter(
            child=child,
            role=role,
            deleted_at__isnull=True,
        )
        .select_related("child", "parent")
        .first()
    )
    if current is None:
        latest = ParentLink.objects.filter(child=child, role=role).order_by("-version").first()
        if latest is not None and version is not None:
            if latest.parent.user_id != child.user_id:
                raise NotFound()
            raise VersionConflict(current=snapshot(latest))
        raise NotFound()
    if current.parent.user_id != child.user_id:
        raise NotFound()
    if version is None or version != current.version:
        raise VersionConflict(
            current=snapshot(current),
            detail="El parentesco fue modificado en otro lugar.",
        )
    current.deleted_at = timezone.now()
    current.version = current.version + 1
    current.save(update_fields=["deleted_at", "version", "updated_at"])
    _refresh_knowledge(child)
    return current


def _refresh_knowledge(child):
    previous = child.genealogy_knowledge
    roles = set(ParentLink.objects.filter(
        child=child, deleted_at__isnull=True
    ).values_list("role", flat=True))
    child.genealogy_knowledge = (
        Rabbit.GenealogyKnowledge.RECORDED
        if roles == {ParentLink.Role.FATHER, ParentLink.Role.MOTHER}
        else Rabbit.GenealogyKnowledge.UNKNOWN
    )
    if previous != child.genealogy_knowledge:
        child.version += 1
        child.save(update_fields=["genealogy_knowledge", "version", "updated_at"])
    record_knowledge(child, previous)


def build_pedigree(animal: Rabbit) -> dict:
    links = list(
        ParentLink.objects.filter(
            deleted_at__isnull=True,
            child__user_id=animal.user_id,
        ).select_related("child", "parent")
    )
    by_child: dict[int, dict[str, ParentLink]] = {}
    children_of: dict[int, list[ParentLink]] = {}
    integrity = []
    for link in links:
        if link.parent.user_id != animal.user_id:
            integrity.append("INCONSISTENT_OWNERSHIP")
            continue
        if link.parent.sex != ("male" if link.role == ParentLink.Role.FATHER else "female"):
            integrity.append("INVALID_PARENT_SEX")
            continue
        by_child.setdefault(link.child_id, {})[link.role] = link
        children_of.setdefault(link.parent_id, []).append(link)

    def node(rabbit: Rabbit, generation: int) -> dict:
        return {
            "uuid": str(rabbit.uuid),
            "name": rabbit.name,
            "sex": rabbit.sex,
            "generation": generation,
            "deleted": rabbit.deleted_at is not None,
            "genealogyKnowledge": rabbit.genealogy_knowledge,
            "relationship": _relationship_for(generation, rabbit.sex),
        }

    def walk(up):
        seen = {animal.id}
        queue = deque([(animal.id, 0)])
        result = []
        while queue:
            rabbit_id, generation = queue.popleft()
            edges = (by_child.get(rabbit_id, {}).values() if up
                     else children_of.get(rabbit_id, []))
            for link in sorted(edges, key=lambda item: str(
                item.parent.uuid if up else item.child.uuid
            )):
                target = link.parent if up else link.child
                if target.id in seen:
                    continue
                seen.add(target.id)
                distance = generation + (1 if up else -1)
                result.append(node(target, distance))
                queue.append((target.id, distance))
        return sorted(result, key=lambda item: (abs(item["generation"]), item["uuid"]))

    ancestors = walk(True)
    descendants = walk(False)
    relevant = {animal.id}
    uuid_ids = {str(link.child.uuid): link.child_id for link in links}
    uuid_ids.update({str(link.parent.uuid): link.parent_id for link in links})
    relevant.update(uuid_ids[item["uuid"]] for item in ancestors + descendants)
    # Kahn's algorithm detects cycles without recursion, including cycles that
    # don't pass through the queried animal.
    indegree = {key: 0 for key in relevant}
    outgoing = {key: [] for key in relevant}
    for child_id, roles in by_child.items():
        for link in roles.values():
            if child_id in relevant and link.parent_id in relevant:
                outgoing[child_id].append(link.parent_id)
                indegree[link.parent_id] += 1
    queue = deque(key for key, count in indegree.items() if count == 0)
    removed = 0
    while queue:
        current = queue.popleft()
        removed += 1
        for target in outgoing[current]:
            indegree[target] -= 1
            if indegree[target] == 0:
                queue.append(target)
    if removed != len(relevant):
        integrity.append("GENEALOGY_CYCLE")
    roles = by_child.get(animal.id, {})
    father = roles.get(ParentLink.Role.FATHER)
    mother = roles.get(ParentLink.Role.MOTHER)
    return {
        "animal": node(animal, 0),
        "father": node(father.parent, 1) if father else None,
        "mother": node(mother.parent, 1) if mother else None,
        "ancestors": ancestors,
        "descendants": descendants,
        "integrity": "INVALID" if integrity else "VALID",
        "integrityIssues": sorted(set(integrity)),
        "links": sorted(
            [public_link(link) for roles in by_child.values() for link in roles.values()
             if link.child_id in relevant and link.parent_id in relevant],
            key=lambda item: (item["child_uuid"], item["role"], item["parent_uuid"]),
        ),
    }


def _relationship_for(generation: int, sex: str) -> str:
    if generation == 0:
        return "CURRENT"
    if generation > 0:
        labels = {
            1: "FATHER" if sex == Rabbit.Sex.MALE else "MOTHER",
            2: "GRANDFATHER" if sex == Rabbit.Sex.MALE else "GRANDMOTHER",
            3: "GREAT_GRANDFATHER" if sex == Rabbit.Sex.MALE else "GREAT_GRANDMOTHER",
            4: "GREAT_GREAT_GRANDFATHER" if sex == Rabbit.Sex.MALE else "GREAT_GREAT_GRANDMOTHER",
        }
        return labels.get(generation, "ANCESTOR")
    distance = abs(generation)
    labels = {
        1: "SON" if sex == Rabbit.Sex.MALE else "DAUGHTER",
        2: "GRANDSON" if sex == Rabbit.Sex.MALE else "GRANDDAUGHTER",
        3: "GREAT_GRANDSON" if sex == Rabbit.Sex.MALE else "GREAT_GRANDDAUGHTER",
        4: "GREAT_GREAT_GRANDSON" if sex == Rabbit.Sex.MALE else "GREAT_GREAT_GRANDDAUGHTER",
    }
    return labels.get(distance, "DESCENDANT")


def _cycle(child_id: int, parent_id: int, links: list[ParentLink]):
    parents_of: dict[int, list[int]] = {}
    for link in links:
        parents_of.setdefault(link.child_id, []).append(link.parent_id)
    visited: set[int] = set()
    frontier = [parent_id]
    depth = 0
    while frontier:
        nxt: list[int] = []
        for node_id in frontier:
            if node_id in visited:
                continue
            visited.add(node_id)
            for ancestor_id in parents_of.get(node_id, []):
                if ancestor_id == child_id:
                    return "direct" if depth == 0 else "indirect"
                nxt.append(ancestor_id)
        depth += 1
        frontier = nxt
    return None
