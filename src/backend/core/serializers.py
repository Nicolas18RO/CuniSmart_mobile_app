from rest_framework import serializers

from .models import Rabbit


class RabbitSerializer(serializers.ModelSerializer):
    class Meta:
        model = Rabbit
        fields = [
            "id",
            "name",
            "breed",
            "sex",
            "birth_date",
            "weight",
            "status",
            "notes",
            "created_at",
            "updated_at",
        ]

