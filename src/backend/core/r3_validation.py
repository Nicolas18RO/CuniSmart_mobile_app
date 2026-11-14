"""Run via python -B -m core.r3_validation [test labels]. Never uses development DB."""
import os
import sys
from unittest.mock import patch

import django
import psycopg2


def main():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "cunismart_backend.settings")
    django.setup()
    from django.conf import settings
    from django.core.management import call_command
    from django.db import connections
    from django.db.backends.postgresql.base import DatabaseWrapper

    name = "test_cunismart_r3_integral_20261109"
    config = connections["default"].settings_dict
    assert config["ENGINE"] == "django.db.backends.postgresql"
    assert name != config["NAME"] and not config["TEST"]["MIRROR"]

    def exists():
        with psycopg2.connect(
            dbname="postgres", user=config["USER"], password=config["PASSWORD"],
            host=config["HOST"], port=config["PORT"], connect_timeout=5,
            options="-c default_transaction_read_only=on",
        ) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1 FROM pg_database WHERE datname=%s", (name,))
                return cursor.fetchone() is not None

    if exists():
        raise RuntimeError("Test database already exists; refusing to overwrite it")
    settings.DATABASES["default"]["TEST"]["NAME"] = name
    config["TEST"]["NAME"] = name
    original = DatabaseWrapper.get_new_connection

    def guarded(wrapper, parameters):
        if parameters.get("dbname") not in ("postgres", name):
            raise RuntimeError("Forbidden database connection")
        return original(wrapper, parameters)

    try:
        with patch.object(DatabaseWrapper, "get_new_connection", guarded):
            call_command("test", *(sys.argv[1:] or ["accounts", "core", "chatbot"]),
                         verbosity=2, interactive=False)
    finally:
        connections.close_all()
        remaining = exists()
        print("TEMPORARY_DATABASE_REMAINS:", remaining)
        if remaining:
            raise RuntimeError("Temporary database remains; manual investigation required")


if __name__ == "__main__":
    main()
