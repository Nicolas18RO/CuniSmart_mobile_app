from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import RabbitViewSet

router = DefaultRouter()
router.register(r"rabbits", RabbitViewSet, basename="rabbit")

urlpatterns = [
    path("", include(router.urls)),
]

