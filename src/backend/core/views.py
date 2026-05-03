from rest_framework import viewsets

from .models import Rabbit
from .serializers import RabbitSerializer


class RabbitViewSet(viewsets.ModelViewSet):
    queryset = Rabbit.objects.all().order_by("-created_at")
    serializer_class = RabbitSerializer
