import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path
from threading import Barrier
from unittest.mock import patch
from uuid import uuid4

from django.contrib.auth import get_user_model
from django.db import IntegrityError, connection, connections, transaction
from django.test import SimpleTestCase, TransactionTestCase

from .models import Rabbit, ReproductiveEvent, SyncOperationReceipt
from .reproductive_service import ReproductiveEventService
from .sync_receipts import (
    ReceiptKeyConflict, ReceiptResult, canonical_command, execute_idempotent,
)


class CanonicalCommandTests(SimpleTestCase):
    def test_shared_vectors(self):
        for stage in ("e7_2", "e7_3"):
            path = Path(__file__).parent / "fixtures" / f"{stage}_commands.json"
            vectors = json.loads(path.read_text(encoding="utf-8"))
            for vector in vectors:
                with self.subTest(stage=stage, command=vector["command"]):
                    command = canonical_command(**vector["command"])
                    self.assertEqual(command.decode("utf-8"), vector["canonical"])
                    self.assertEqual(hashlib.sha256(command).hexdigest(), vector["sha256"])


class ReceiptTests(TransactionTestCase):
    def setUp(self):
        self.owner = self.make_owner("one")
        self.key = uuid4()
        self.command = {
            "entity_type": "REPRODUCTIVE_EVENT", "action": "CREATE",
            "destination": "/reproductive-events/", "payload": {"notes": "Cría"},
        }

    def make_owner(self, label):
        model = get_user_model()
        return model.objects.create_user(
            **{model.USERNAME_FIELD: f"{label}@example.test"}, password="test-password",
        )

    def effect(self, owner):
        rabbits = [
            Rabbit.objects.create(user=owner, name=sex, breed="Rex", sex=sex,
                                  birth_date=date(2024, 1, 1), status="active")
            for sex in ("male", "female")
        ]
        event = ReproductiveEventService().create(
            owner_id=owner.pk, male_uuid=rabbits[0].uuid, female_uuid=rabbits[1].uuid,
            mating_date=date(2025, 1, 1), notes="Cría",
        )
        identity = {"uuid": str(event.uuid)}
        return ReceiptResult(201, identity, remote_identity=identity, remote_version=1)

    def run_command(self, *, owner=None, effect=None, **overrides):
        owner = owner or self.owner
        return execute_idempotent(
            owner=owner, operation_uuid=self.key, effect=effect or (lambda: self.effect(owner)),
            **(self.command | overrides),
        )

    def test_lost_response_replay_and_mismatch(self):
        first = self.run_command()
        replay = self.run_command(effect=lambda: self.fail("replayed effect"))
        self.assertEqual((replay.pk, replay.response_body, replay.status_code),
                         (first.pk, first.response_body, 201))
        with self.assertRaises(ReceiptKeyConflict):
            self.run_command(payload={"notes": None})
        self.assertEqual(ReproductiveEvent.objects.count(), 1)
        self.assertEqual(SyncOperationReceipt.objects.count(), 1)

    def test_owner_isolation_and_database_unique_constraint(self):
        first = self.run_command()
        second = self.run_command(owner=self.make_owner("two"))
        self.assertNotEqual(first.remote_identity, second.remote_identity)
        with self.assertRaises(IntegrityError), transaction.atomic():
            first.pk = None
            first.save(force_insert=True)
        self.assertEqual(SyncOperationReceipt.objects.count(), 2)

    def test_failed_insert_and_domain_failure_roll_back_effect(self):
        with patch.object(SyncOperationReceipt.objects, "create",
                          side_effect=IntegrityError("injected receipt failure")):
            with self.assertRaises(IntegrityError):
                self.run_command()
        self.assertEqual(Rabbit.objects.count(), 0)
        self.assertEqual(ReproductiveEvent.objects.count(), 0)
        self.assertEqual(SyncOperationReceipt.objects.count(), 0)

        def fail_after_write():
            self.effect(self.owner)
            raise ValueError("injected domain failure")

        with self.assertRaises(ValueError):
            self.run_command(effect=fail_after_write)
        self.assertEqual(Rabbit.objects.count(), 0)
        self.assertEqual(self.run_command().status_code, 201)

    def test_concurrent_real_connections_commit_one_effect(self):
        if connection.vendor != "postgresql":
            self.skipTest("PostgreSQL row locks required")
        barrier = Barrier(2)

        def worker():
            try:
                barrier.wait(timeout=10)
                return self.run_command().pk
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=2) as pool:
            first, second = [pool.submit(worker) for _ in range(2)]
            self.assertEqual(first.result(timeout=20), second.result(timeout=20))
        self.assertEqual(ReproductiveEvent.objects.count(), 1)
        self.assertEqual(SyncOperationReceipt.objects.count(), 1)
