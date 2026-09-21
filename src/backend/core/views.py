from rest_framework import viewsets

from .models import Rabbit, SensorReading
from .serializers import RabbitSerializer, SensorReadingSerializer


class RabbitViewSet(viewsets.ModelViewSet):
    queryset = Rabbit.objects.all().order_by("-created_at")
    serializer_class = RabbitSerializer


class SensorReadingViewSet(viewsets.ModelViewSet):
    queryset = SensorReading.objects.select_related("rabbit", "sensor_device").all()
    serializer_class = SensorReadingSerializer
