import uuid

from django.conf import settings
from django.db import models


class Rabbit(models.Model):
    class GenealogyKnowledge(models.TextChoices):
        UNKNOWN = "UNKNOWN", "Unknown"
        FOUNDER = "FOUNDER", "Declared founder"
        RECORDED = "RECORDED", "Both parents recorded"

    class Sex(models.TextChoices):
        MALE = "male", "Male"
        FEMALE = "female", "Female"

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        SOLD = "sold", "Sold"
        DECEASED = "deceased", "Deceased"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="rabbits",
    )
    uuid = models.UUIDField(default=uuid.uuid4, unique=True)
    name = models.CharField(max_length=120)
    breed = models.CharField(max_length=120)
    sex = models.CharField(max_length=10, choices=Sex.choices)
    birth_date = models.DateField()

    weight = models.FloatField(null=True, blank=True)
    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.ACTIVE,
    )
    notes = models.TextField(blank=True)
    genealogy_knowledge = models.CharField(
        max_length=8, choices=GenealogyKnowledge.choices,
        default=GenealogyKnowledge.UNKNOWN,
    )
    version = models.PositiveIntegerField(default=1)
    deleted_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return self.name


class GenealogyTransition(models.Model):
    rabbit = models.ForeignKey(Rabbit, on_delete=models.PROTECT, related_name="genealogy_transitions")
    previous = models.CharField(max_length=8)
    current = models.CharField(max_length=8)
    created_at = models.DateTimeField(auto_now_add=True)


class ParentLink(models.Model):
    """One active father or mother edge. The rabbit UUID stays the identity."""

    class Role(models.TextChoices):
        FATHER = "FATHER", "Father"
        MOTHER = "MOTHER", "Mother"

    child = models.ForeignKey(
        Rabbit,
        on_delete=models.PROTECT,
        related_name="parent_links",
    )
    parent = models.ForeignKey(
        Rabbit,
        on_delete=models.PROTECT,
        related_name="offspring_links",
    )
    role = models.CharField(max_length=6, choices=Role.choices)
    cycle_uuid = models.UUIDField(default=uuid.uuid4, unique=True, null=True, editable=False)
    creation_version = models.PositiveIntegerField(null=True, editable=False)
    version = models.PositiveIntegerField(default=1)
    deleted_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.CheckConstraint(condition=~models.Q(child=models.F("parent")), name="parent_not_self"),
            models.CheckConstraint(condition=models.Q(role__in=["FATHER", "MOTHER"]), name="parent_valid_role"),
            models.CheckConstraint(condition=models.Q(version__gte=1), name="parent_positive_version"),
            models.UniqueConstraint(
                fields=["child", "role"],
                condition=models.Q(deleted_at__isnull=True),
                name="uniq_active_parent_role",
            )
        ]

    def __str__(self) -> str:
        return f"{self.role} {self.parent_id} -> {self.child_id}"


class R3ReadSnapshot(models.Model):
    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    entity = models.CharField(max_length=24)
    scope = models.JSONField()
    items = models.JSONField()
    page_size = models.PositiveIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)


class ReproductiveEvent(models.Model):
    """Persisted reproductive record; domain rules live outside the ORM."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reproductive_events",
    )
    uuid = models.UUIDField(default=uuid.uuid4, unique=True)
    male = models.ForeignKey(
        Rabbit,
        on_delete=models.PROTECT,
        related_name="reproductive_events_as_male",
    )
    female = models.ForeignKey(
        Rabbit,
        on_delete=models.PROTECT,
        related_name="reproductive_events_as_female",
    )
    mating_date = models.DateField()
    estimated_birth_date = models.DateField()
    notes = models.TextField(blank=True)
    version = models.PositiveIntegerField(default=1)
    deleted_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["estimated_birth_date", "uuid"]
        constraints = [
            models.CheckConstraint(
                condition=~models.Q(male=models.F("female")),
                name="reproductive_distinct_rabbits",
            ),
            models.CheckConstraint(
                condition=models.Q(version__gte=1),
                name="reproductive_positive_version",
            ),
        ]

    def __str__(self) -> str:
        return f"ReproductiveEvent({self.uuid})"


class SensorDevice(models.Model):
    """Physical sensor node (ESP32, etc.); not tied to a single rabbit."""

    class Type(models.TextChoices):
        TEMPERATURE = "temperature", "Temperature"
        WATER = "water", "Water"
        WEIGHT_SCALE = "weight_scale", "Weight scale"

    class Location(models.TextChoices):
        ROOM = "room", "Room"
        TANK = "tank", "Tank"
        SCALE = "scale", "Scale"

    type = models.CharField(max_length=20, choices=Type.choices)
    location = models.CharField(max_length=10, choices=Location.choices)

    class Meta:
        ordering = ["id"]

    def __str__(self) -> str:
        return f"{self.get_type_display()} @ {self.get_location_display()}"


class SyncOperationReceipt(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    operation_uuid = models.UUIDField()
    entity_type = models.CharField(max_length=32)
    action = models.CharField(max_length=16)
    contract_version = models.PositiveSmallIntegerField()
    request_hash = models.CharField(max_length=64)
    remote_identity = models.JSONField(null=True)
    remote_version = models.PositiveIntegerField(null=True)
    status_code = models.PositiveSmallIntegerField()
    response_body = models.JSONField(null=True)
    body_present = models.BooleanField(default=True)
    confirmed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=("owner", "operation_uuid"), name="sync_receipt_owner_operation",
            ),
        ]

class SensorReading(models.Model):
    """Sample from a SensorDevice; rabbit is optional (e.g. weight event)."""

    sensor_device = models.ForeignKey(
        SensorDevice,
        on_delete=models.CASCADE,
        related_name="readings",
    )
    rabbit = models.ForeignKey(
        Rabbit,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="sensor_readings",
    )
    temperature = models.FloatField(null=True, blank=True)
    weight = models.FloatField(null=True, blank=True)
    water_level = models.FloatField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"SensorReading(device={self.sensor_device_id}, rabbit={self.rabbit_id}, {self.created_at})"
