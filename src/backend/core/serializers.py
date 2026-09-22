from rest_framework import serializers

from .exceptions import VersionConflict
from .models import Rabbit, SensorDevice, SensorReading


class RabbitSerializer(serializers.ModelSerializer):
    class Meta:
        model = Rabbit
        fields = [
            "id",
            "uuid",
            "user",
            "name",
            "breed",
            "sex",
            "birth_date",
            "weight",
            "status",
            "notes",
            "version",
            "deleted_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "user",
            "deleted_at",
            "created_at",
            "updated_at",
        ]
        extra_kwargs = {
            "uuid": {"required": False},
            "version": {"required": False},
        }

    def create(self, validated_data):
        validated_data.pop("version", None)
        return super().create(validated_data)

    def update(self, instance, validated_data):
        validated_data.pop("uuid", None)
        incoming = validated_data.pop("version", None)
        if incoming is not None and incoming != instance.version:
            raise VersionConflict(current=RabbitSerializer(instance).data)
        validated_data["version"] = instance.version + 1
        return super().update(instance, validated_data)

    def validate_weight(self, value):
        if value is not None and value < 0:
            raise serializers.ValidationError("El peso no puede ser negativo.")
        return value


def _default_legacy_combined_device() -> SensorDevice:
    """Pre-infrastructure rows used one reading with rabbit + all metrics."""
    device = (
        SensorDevice.objects.filter(type=SensorDevice.Type.WEIGHT_SCALE, location=SensorDevice.Location.SCALE)
        .order_by("pk")
        .first()
    )
    if device:
        return device
    return SensorDevice.objects.create(
        type=SensorDevice.Type.WEIGHT_SCALE,
        location=SensorDevice.Location.SCALE,
    )


class SensorReadingSerializer(serializers.ModelSerializer):
    """sensor_device optional on create for clients that still POST rabbit-only payloads."""

    sensor_device = serializers.PrimaryKeyRelatedField(
        queryset=SensorDevice.objects.all(),
        required=False,
        allow_null=True,
    )

    class Meta:
        model = SensorReading
        fields = [
            "id",
            "sensor_device",
            "rabbit",
            "temperature",
            "weight",
            "water_level",
            "created_at",
        ]
        read_only_fields = ["id", "created_at"]

    def validate(self, attrs):
        if self.instance is not None:
            return attrs
        if any(attrs.get(k) is not None for k in ("temperature", "weight", "water_level")):
            return attrs
        raise serializers.ValidationError(
            "At least one of temperature, weight, or water_level is required."
        )

    def create(self, validated_data):
        if validated_data.get("sensor_device") is None:
            validated_data["sensor_device"] = _default_legacy_combined_device()
        return super().create(validated_data)
