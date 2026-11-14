"""Owner-scoped graph projection shared by E4 and reproductive use cases."""
from .kinship import Animal
from .models import ParentLink, Rabbit


def herd_for_owner(user):
    rabbits = list(Rabbit.objects.filter(user=user))
    fathers: dict[str, str] = {}
    mothers: dict[str, str] = {}
    invalid = set()
    links = ParentLink.objects.filter(
        deleted_at__isnull=True, child__user=user,
    ).select_related("child", "parent")
    for link in links:
        key = str(link.child.uuid)
        if (link.parent.user_id != user.pk or link.parent.deleted_at is not None
                or link.child.deleted_at is not None
                or link.parent.sex != ("male" if link.role == "FATHER" else "female")):
            invalid.add(key)
            continue
        parent = str(link.parent.uuid)
        if link.role == ParentLink.Role.FATHER:
            fathers[key] = parent
        else:
            mothers[key] = parent
    return {
        str(rabbit.uuid): Animal(
            str(rabbit.uuid), fathers.get(str(rabbit.uuid)),
            mothers.get(str(rabbit.uuid)),
            knowledge=("UNKNOWN" if str(rabbit.uuid) in invalid or rabbit.deleted_at
                       else rabbit.genealogy_knowledge),
            name=rabbit.name,
            sex=rabbit.sex,
        )
        for rabbit in rabbits
    }
