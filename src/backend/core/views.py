import uuid

from django.utils import timezone
from rest_framework import viewsets
from rest_framework.exceptions import NotFound
from rest_framework.permissions import IsAuthenticated

from .models import Rabbit, SensorReading
from .serializers import RabbitSerializer, SensorReadingSerializer


class RabbitViewSet(viewsets.ModelViewSet):
    serializer_class = RabbitSerializer
    permission_classes = [IsAuthenticated]
    lookup_value_regex = r"[^/]+"

    def get_queryset(self):
        return Rabbit.objects.filter(
            user=self.request.user,
            deleted_at__isnull=True,
        ).order_by("-created_at")

    def get_object(self):
        queryset = self.filter_queryset(self.get_queryset())
        raw = self.kwargs[self.lookup_field]
        rabbit = self._find_rabbit(queryset, raw)
        if rabbit is None:
            raise NotFound()
        self.check_object_permissions(self.request, rabbit)
        return rabbit

    def _find_rabbit(self, queryset, raw):
        parsed = None
        try:
            parsed = uuid.UUID(str(raw))
        except (ValueError, AttributeError, TypeError):
            parsed = None
        if parsed is not None:
            found = queryset.filter(uuid=parsed).first()
            if found is not None:
                return found
        if str(raw).isdigit():
            return queryset.filter(pk=int(raw)).first()
        return None

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    def perform_destroy(self, instance):
        if instance.deleted_at is None:
            instance.deleted_at = timezone.now()
            instance.version = instance.version + 1
            instance.save(update_fields=["deleted_at", "version", "updated_at"])


class SensorReadingViewSet(viewsets.ModelViewSet):
    queryset = SensorReading.objects.select_related("rabbit", "sensor_device").all()
    serializer_class = SensorReadingSerializer
