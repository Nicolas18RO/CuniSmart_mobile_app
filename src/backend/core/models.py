from django.db import models


class Rabbit(models.Model):
    class Sex(models.TextChoices):
        MALE = "male", "Male"
        FEMALE = "female", "Female"

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        SOLD = "sold", "Sold"
        DECEASED = "deceased", "Deceased"

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

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return self.name


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
