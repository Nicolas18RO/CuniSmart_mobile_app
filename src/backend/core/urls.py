from django.urls import include, path
from rest_framework.routers import DefaultRouter
from .r3_snapshots import R3SnapshotPageView, R3SnapshotView

from .views import (
    KinshipView,
    ParentLinkView,
    PedigreeView,
    RabbitViewSet,
    ReproductiveEventViewSet,
    SensorReadingViewSet,
)

router = DefaultRouter()
router.register(r"rabbits", RabbitViewSet, basename="rabbit")
router.register(r"reproductive-events", ReproductiveEventViewSet, basename="reproductive-event")
router.register(
    r"sensor-readings",
    SensorReadingViewSet,
    basename="sensorreading",
)

urlpatterns = [
    path("r3/v1/snapshots/", R3SnapshotView.as_view()),
    path("r3/v1/snapshots/<uuid:snapshot_uuid>/", R3SnapshotPageView.as_view()),
    path("rabbits/kinship/", KinshipView.as_view()),
    path("rabbits/<uuid:rabbit_uuid>/pedigree/", PedigreeView.as_view()),
    path(
        "rabbits/<uuid:rabbit_uuid>/parents/<str:role>/",
        ParentLinkView.as_view(),
    ),
    path(
        "rabbits/<uuid:rabbit_uuid>/parents/<str:role>/replace/",
        ParentLinkView.as_view(),
    ),
    path("", include(router.urls)),
]

