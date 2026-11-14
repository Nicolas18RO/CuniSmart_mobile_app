"""ORM access for reproductive application services."""
from .models import Rabbit, ReproductiveEvent
from .genealogy_herd import herd_for_owner


class ReproductiveEventRepository:
    def active_for_owner(self, owner_id):
        return ReproductiveEvent.objects.filter(
            user_id=owner_id, deleted_at__isnull=True,
        ).select_related("male", "female")

    def event(self, owner_id, event_uuid):
        return self.active_for_owner(owner_id).filter(uuid=event_uuid).first()

    def rabbit(self, owner_id, rabbit_uuid):
        return Rabbit.objects.filter(user_id=owner_id, uuid=rabbit_uuid).first()

    def create(self, **values):
        return ReproductiveEvent.objects.create(**values)

    def herd(self, owner_id):
        user_model = Rabbit._meta.get_field("user").remote_field.model
        return herd_for_owner(user_model.objects.get(pk=owner_id))
