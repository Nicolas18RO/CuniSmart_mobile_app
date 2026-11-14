from rest_framework import serializers

from .exceptions import VersionConflict
from .models import Rabbit, SensorDevice, SensorReading
from .genealogy_transactions import owner_write, record_knowledge
from .reproductive_domain import ReproductiveRuleError
from .reproductive_service import ReproductiveEventService


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
            "genealogy_knowledge",
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
        with owner_write(validated_data["user"].pk):
            instance = super().create(validated_data)
            record_knowledge(instance, "UNKNOWN")
            return instance

    def update(self, instance, validated_data):
        with owner_write(instance.user_id):
            instance.refresh_from_db()
            self.validate(validated_data)
            previous = instance.genealogy_knowledge
            result = self._update_locked(instance, validated_data)
            record_knowledge(result, previous)
            return result

    def _update_locked(self, instance, validated_data):
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

    def validate(self, attrs):
        knowledge = attrs.get("genealogy_knowledge")
        if knowledge is not None and self.instance is not None:
            version = attrs.get("version")
            if type(version) is not int or not 1 <= version <= 2147483647:
                raise serializers.ValidationError("Se requiere una versión entera válida para cambiar el conocimiento.")
        if knowledge == Rabbit.GenealogyKnowledge.RECORDED:
            raise serializers.ValidationError(
                "El estado RECORDED se obtiene registrando ambos progenitores."
            )
        if self.instance is not None:
            links = self.instance.offspring_links.filter(deleted_at__isnull=True)
            sex = attrs.get("sex", self.instance.sex)
            incompatible = links.exclude(
                role="FATHER" if sex == Rabbit.Sex.MALE else "MOTHER"
            )
            if incompatible.exists():
                raise serializers.ValidationError("El sexo es incompatible con sus relaciones activas.")
            try:
                ReproductiveEventService().assert_rabbit_mutation_allowed(
                    self.instance, new_sex=sex,
                )
            except ReproductiveRuleError as error:
                raise serializers.ValidationError(str(error))
            if knowledge == Rabbit.GenealogyKnowledge.FOUNDER and self.instance.parent_links.filter(
                deleted_at__isnull=True
            ).exists():
                raise serializers.ValidationError("Un fundador no puede tener progenitores activos.")
        return attrs


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


class ReproductiveEventWriteSerializer(serializers.Serializer):
    male_uuid = serializers.UUIDField(required=False)
    female_uuid = serializers.UUIDField(required=False)
    mating_date = serializers.DateField(required=False)
    notes = serializers.CharField(required=False, allow_blank=True, max_length=4000)
    version = serializers.IntegerField(required=False, min_value=1, max_value=2147483647)

    def validate_version(self, value):
        if type(value) is not int:
            raise serializers.ValidationError("La versión debe ser un entero.")
        return value
