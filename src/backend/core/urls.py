from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import RabbitViewSet, SensorReadingViewSet

router = DefaultRouter()
router.register(r"rabbits", RabbitViewSet, basename="rabbit")
router.register(
    r"sensor-readings",
    SensorReadingViewSet,
    basename="sensorreading",
)

urlpatterns = [
    path("", include(router.urls)),
]

