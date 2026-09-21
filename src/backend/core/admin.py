from django.contrib import admin

from .models import SensorDevice, SensorReading


@admin.register(SensorDevice)
class SensorDeviceAdmin(admin.ModelAdmin):
    list_display = ("id", "type", "location")


@admin.register(SensorReading)
class SensorReadingAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "sensor_device",
        "rabbit",
        "temperature",
        "weight",
        "water_level",
        "created_at",
    )
    list_filter = ("sensor_device__type",)
