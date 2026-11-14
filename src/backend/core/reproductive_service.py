"""Application use cases for reproductive events and their calendar."""
from datetime import date

from django.utils import timezone

from .exceptions import VersionConflict
from .genealogy_transactions import owner_write
from .kinship import evaluate
from .reproductive_domain import (
    RabbitFacts, ReproductiveRuleError, calendar_state, estimated_birth_date,
    validate_calendar_range, validate_pair,
)
from .reproductive_repository import ReproductiveEventRepository


def _facts(rabbit):
    return RabbitFacts(
        str(rabbit.uuid), rabbit.user_id, rabbit.sex, rabbit.status,
        rabbit.deleted_at is not None,
    )


class ReproductiveEventService:
    def __init__(self, repository=None):
        self.repository = repository or ReproductiveEventRepository()

    def create(self, *, owner_id, male_uuid, female_uuid, mating_date, notes=""):
        with owner_write(owner_id):
            male = self.repository.rabbit(owner_id, male_uuid)
            female = self.repository.rabbit(owner_id, female_uuid)
            if male is None or female is None:
                raise ReproductiveRuleError("Uno de los animales no existe para este propietario.")
            validate_pair(_facts(male), _facts(female), owner_id)
            estimated = estimated_birth_date(mating_date)
            return self.repository.create(
                user_id=owner_id, male=male, female=female,
                mating_date=mating_date, estimated_birth_date=estimated,
                notes=notes,
            )

    def assert_rabbit_mutation_allowed(self, rabbit, *, new_sex=None, deleting=False):
        events = self.repository.active_for_owner(rabbit.user_id)
        as_male = events.filter(male_id=rabbit.pk).exists()
        as_female = events.filter(female_id=rabbit.pk).exists()
        if deleting and (as_male or as_female):
            raise ReproductiveRuleError(
                "No se puede eliminar un animal con eventos reproductivos activos."
            )
        sex = new_sex or rabbit.sex
        if (as_male and sex != "male") or (as_female and sex != "female"):
            raise ReproductiveRuleError(
                "El sexo es incompatible con sus eventos reproductivos activos."
            )

    def update(self, *, owner_id, event_uuid, version, mating_date=None, notes=None):
        with owner_write(owner_id):
            event = self.repository.event(owner_id, event_uuid)
            if event is None:
                return None
            if version != event.version:
                raise VersionConflict(current=self.payload(event))
            validate_pair(_facts(event.male), _facts(event.female), owner_id)
            fields = ["version", "updated_at"]
            if mating_date is not None:
                event.mating_date = mating_date
                event.estimated_birth_date = estimated_birth_date(mating_date)
                fields.extend(["mating_date", "estimated_birth_date"])
            if notes is not None:
                event.notes = notes
                fields.append("notes")
            event.version += 1
            event.save(update_fields=fields)
            return event

    def delete(self, *, owner_id, event_uuid, version):
        with owner_write(owner_id):
            event = self.repository.event(owner_id, event_uuid)
            if event is None:
                return None
            if version != event.version:
                raise VersionConflict(current=self.payload(event))
            event.deleted_at = timezone.now()
            event.version += 1
            event.save(update_fields=["deleted_at", "version", "updated_at"])
            return event

    def list(self, owner_id):
        return self.repository.active_for_owner(owner_id)

    def list_payloads(self, owner_id, *, today=None):
        herd = self.repository.herd(owner_id)
        return [self.payload(event, today=today, herd=herd) for event in self.list(owner_id)]

    def get(self, owner_id, event_uuid):
        return self.repository.event(owner_id, event_uuid)

    def calendar(self, *, owner_id, start_date, end_date, today=None):
        validate_calendar_range(start_date, end_date)
        reference = today or timezone.localdate()
        events = self.repository.active_for_owner(owner_id).filter(
            estimated_birth_date__gte=start_date,
            estimated_birth_date__lte=end_date,
        )
        herd = self.repository.herd(owner_id)
        return [self.payload(event, today=reference, herd=herd) for event in events]

    @staticmethod
    def payload(event, today=None, herd=None):
        reference = today or timezone.localdate()
        result = {
            "uuid": str(event.uuid),
            "male_uuid": str(event.male.uuid),
            "male_name": event.male.name,
            "female_uuid": str(event.female.uuid),
            "female_name": event.female.name,
            "mating_date": event.mating_date.isoformat(),
            "estimated_birth_date": event.estimated_birth_date.isoformat(),
            "notes": event.notes,
            "version": event.version,
            "created_at": event.created_at.isoformat() if event.created_at else None,
            "updated_at": event.updated_at.isoformat() if event.updated_at else None,
            "calendar_state": calendar_state(event.estimated_birth_date, reference),
            "days_remaining": (event.estimated_birth_date - reference).days,
        }
        if herd is not None:
            result["kinship_evaluation"] = evaluate(
                str(event.male.uuid), str(event.female.uuid), herd,
            ).to_payload()
        return result

    def full_payload(self, event, *, today=None):
        return self.payload(event, today=today, herd=self.repository.herd(event.user_id))
