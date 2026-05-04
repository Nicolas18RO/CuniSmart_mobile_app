import random
import time

from django.core.management.base import BaseCommand

from core.models import Rabbit, SensorDevice, SensorReading


def _first_or_create_device(type_: str, location: str) -> SensorDevice:
    d = SensorDevice.objects.filter(type=type_, location=location).order_by("pk").first()
    if d:
        return d
    return SensorDevice.objects.create(type=type_, location=location)


class Command(BaseCommand):
    help = (
        "Simulate infrastructure sensors: room temperature, tank level, and "
        "optional per-rabbit weight events each interval (default 5s). Ctrl+C to stop."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--interval",
            type=float,
            default=5.0,
            help="Seconds between simulation ticks (default: 5).",
        )

    def handle(self, *args, **options):
        interval = max(0.5, options["interval"])
        self.stdout.write(
            self.style.SUCCESS(
                f"Simulating sensor readings every {interval}s (Ctrl+C to stop)."
            )
        )
        temp_dev = _first_or_create_device(
            SensorDevice.Type.TEMPERATURE,
            SensorDevice.Location.ROOM,
        )
        water_dev = _first_or_create_device(
            SensorDevice.Type.WATER,
            SensorDevice.Location.TANK,
        )
        scale_dev = _first_or_create_device(
            SensorDevice.Type.WEIGHT_SCALE,
            SensorDevice.Location.SCALE,
        )
        try:
            while True:
                SensorReading.objects.create(
                    sensor_device=temp_dev,
                    rabbit=None,
                    temperature=round(random.uniform(16.0, 28.0), 1),
                    weight=None,
                    water_level=None,
                )
                SensorReading.objects.create(
                    sensor_device=water_dev,
                    rabbit=None,
                    temperature=None,
                    weight=None,
                    water_level=round(random.uniform(25.0, 100.0), 1),
                )
                rabbits = list(Rabbit.objects.all())
                if not rabbits:
                    self.stdout.write("No rabbits in DB; skipping weight readings this tick.")
                for rabbit in rabbits:
                    base_weight = (
                        rabbit.weight
                        if rabbit.weight is not None
                        else random.uniform(1.2, 4.0)
                    )
                    SensorReading.objects.create(
                        sensor_device=scale_dev,
                        rabbit=rabbit,
                        temperature=None,
                        weight=round(
                            max(0.3, base_weight + random.uniform(-0.2, 0.2)), 2
                        ),
                        water_level=None,
                    )
                time.sleep(interval)
        except KeyboardInterrupt:
            self.stdout.write(self.style.WARNING("Simulation stopped."))
