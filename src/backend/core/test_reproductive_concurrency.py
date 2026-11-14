from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

from django.db import connection, connections
from django.test import TransactionTestCase
from rest_framework.exceptions import APIException
from rest_framework.test import APIClient

from core.models import Rabbit
from core.reproductive_service import ReproductiveEventService
from core.tests import _make_verified_user


class ReproductiveConcurrencyTests(TransactionTestCase):
    def setUp(self):
        self.assertEqual(connection.vendor, "postgresql")
        self.owner = _make_verified_user(email="reproductive-race@example.test")
        self.male = self.rabbit("M", "male")
        self.female = self.rabbit("F", "female")
        self.event = ReproductiveEventService().create(
            owner_id=self.owner.pk, male_uuid=self.male.uuid,
            female_uuid=self.female.uuid, mating_date=__import__("datetime").date(2026, 10, 1),
        )

    def rabbit(self, name, sex):
        return Rabbit.objects.create(
            user=self.owner, name=name, breed="test", sex=sex, birth_date="2025-01-01",
        )

    def test_same_version_updates_have_one_winner_and_no_partial_write(self):
        barrier = Barrier(2)

        def update(notes):
            try:
                barrier.wait(timeout=10)
                result = ReproductiveEventService().update(
                    owner_id=self.owner.pk, event_uuid=self.event.uuid,
                    version=1, notes=notes,
                )
                return 200, result.notes
            except APIException as error:
                return error.status_code, None
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = [future.result(timeout=30) for future in [
                pool.submit(update, "uno"), pool.submit(update, "dos"),
            ]]
        self.assertCountEqual([status for status, _ in results], [200, 409])
        self.event.refresh_from_db()
        self.assertEqual(self.event.version, 2)
        self.assertIn(self.event.notes, ["uno", "dos"])

    def test_create_event_vs_sex_edit_leaves_pair_valid(self):
        self.event.delete()
        barrier = Barrier(2)

        def create():
            try:
                barrier.wait(timeout=10)
                ReproductiveEventService().create(
                    owner_id=self.owner.pk, male_uuid=self.male.uuid,
                    female_uuid=self.female.uuid,
                    mating_date=__import__("datetime").date(2026, 10, 1),
                )
                return 201
            except (APIException, ValueError) as error:
                return getattr(error, "status_code", 400)
            finally:
                connections.close_all()

        def edit():
            try:
                barrier.wait(timeout=10)
                client = APIClient()
                client.force_authenticate(self.owner)
                return client.patch(
                    f"/api/rabbits/{self.male.uuid}/", {"sex": "female"}, format="json",
                ).status_code
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = [future.result(timeout=30) for future in [
                pool.submit(create), pool.submit(edit),
            ]]
        self.male.refresh_from_db()
        active = self.owner.reproductive_events.filter(deleted_at=None).exists()
        # The barrier starts both requests together. Either can take the owner
        # lock first, but their status and committed state must agree.
        self.assertIn(
            (*results, self.male.sex, active),
            [(201, 400, "male", True), (400, 200, "female", False)],
        )
