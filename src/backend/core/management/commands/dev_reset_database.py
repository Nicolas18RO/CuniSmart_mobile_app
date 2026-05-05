"""
Development-only: reset PostgreSQL public schema and re-run all migrations.

Fixes InconsistentMigrationHistory (e.g. admin applied before accounts User model)
by wiping tables and migration records together.

Usage (from src/backend):
  python manage.py dev_reset_database --yes

Requires DEBUG=True. Destroys all data in the configured database.
"""

from django.conf import settings
from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError
from django.db import connection


class Command(BaseCommand):
    help = "DEV ONLY: DROP/CREATE public schema (PostgreSQL), then migrate."

    def add_arguments(self, parser):
        parser.add_argument(
            "--yes",
            action="store_true",
            help="Confirm destructive reset.",
        )

    def handle(self, *args, **options):
        if not options["yes"]:
            raise CommandError("Refusing to run without --yes (destructive).")

        if not settings.DEBUG:
            raise CommandError("Refusing when DEBUG=False.")

        engine = settings.DATABASES["default"]["ENGINE"]
        if "postgresql" not in engine:
            raise CommandError(
                "This command only supports PostgreSQL. "
                "For SQLite, delete the database file and run: python manage.py migrate"
            )

        self.stdout.write(
            self.style.WARNING(
                "Wiping schema public (all tables + django_migrations). "
                "Custom User model code is unchanged."
            )
        )

        connection.close()
        with connection.cursor() as cursor:
            cursor.execute("DROP SCHEMA IF EXISTS public CASCADE;")
            cursor.execute("CREATE SCHEMA public;")
            cursor.execute("GRANT ALL ON SCHEMA public TO PUBLIC;")

        connection.close()

        self.stdout.write("Applying migrations (order follows Django dependencies)...")
        call_command("migrate", interactive=False, verbosity=1)

        self.stdout.write(
            self.style.SUCCESS(
                "Migration state is clean. Test register/login with createsuperuser if needed."
            )
        )
