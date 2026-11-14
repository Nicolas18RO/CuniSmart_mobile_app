"""Real PostgreSQL connections and simultaneous graph/Rabbit mutations."""
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

from django.db import connection, connections
from django.test import TransactionTestCase
from rest_framework.exceptions import APIException
from rest_framework.test import APIClient

from core.genealogy import assign_or_update, clear_parent
from core.models import ParentLink, Rabbit
from core.tests import _make_verified_user


class GraphConcurrencyTests(TransactionTestCase):
    def setUp(self):
        self.assertEqual(connection.vendor, "postgresql")
        self.owner = _make_verified_user(email="race@example.test")
        self.child = self.rabbit("child")
        self.first = self.rabbit("first")
        self.second = self.rabbit("second")
        self.third = self.rabbit("third")

    def rabbit(self, name):
        return Rabbit.objects.create(
            user=self.owner, name=name, breed="test", sex="male",
            birth_date="2025-01-01",
        )

    def race(self, *operations):
        barrier = Barrier(len(operations))

        def run(operation):
            try:
                barrier.wait(timeout=15)
                operation()
                return 200
            except APIException as error:
                return error.status_code
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=len(operations)) as pool:
            futures = [pool.submit(run, operation) for operation in operations]
            return [future.result(timeout=30) for future in futures]

    def assign(self, parent, version=None, child=None):
        return assign_or_update(
            child=Rabbit.objects.get(pk=(child or self.child).pk),
            parent=Rabbit.objects.get(pk=parent.pk), role="FATHER", version=version,
        )

    def test_simultaneous_create_has_one_winner(self):
        results = self.race(lambda: self.assign(self.first), lambda: self.assign(self.second))
        self.assertCountEqual(results, [200, 409])
        self.assertEqual(ParentLink.objects.filter(deleted_at=None).count(), 1)

    def test_same_version_replacements_have_one_winner(self):
        self.assign(self.first)
        results = self.race(lambda: self.assign(self.second, 1), lambda: self.assign(self.third, 1))
        self.assertCountEqual(results, [200, 409])
        link = ParentLink.objects.get(deleted_at=None)
        self.assertEqual(link.version, 2)
        self.assertIn(link.parent_id, [self.second.pk, self.third.pk])

    def test_concurrent_cycle_is_rejected_without_partial_writes(self):
        results = self.race(
            lambda: self.assign(self.first),
            lambda: self.assign(self.child, child=self.first),
        )
        self.assertCountEqual(results, [200, 400])
        self.assertEqual(ParentLink.objects.count(), 1)

    def test_delete_and_replace_cannot_both_commit(self):
        self.assign(self.first)
        results = self.race(
            lambda: clear_parent(child=Rabbit.objects.get(pk=self.child.pk), role="FATHER", version=1),
            lambda: self.assign(self.second, 1),
        )
        self.assertCountEqual(results, [200, 409])
        self.assertEqual(ParentLink.objects.count(), 1)

    def test_simultaneous_deletes_have_one_winner(self):
        self.assign(self.first)
        def delete():
            clear_parent(child=Rabbit.objects.get(pk=self.child.pk), role="FATHER", version=1)
        self.assertCountEqual(self.race(delete, delete), [200, 409])
        self.assertEqual(ParentLink.objects.filter(deleted_at=None).count(), 0)

    def test_sex_edit_and_assignment_leave_valid_graph(self):
        def edit():
            client = APIClient()
            client.force_authenticate(self.owner)
            response = client.patch(
                f"/api/rabbits/{self.first.uuid}/", {"sex": "female", "version": 1}, format="json",
            )
            if response.status_code != 200:
                from rest_framework.exceptions import ValidationError
                self.assertEqual(response.status_code, 400)
                raise ValidationError()

        results = self.race(edit, lambda: self.assign(self.first))
        self.assertCountEqual(results, [200, 400])
        self.first.refresh_from_db()
        if ParentLink.objects.exists():
            self.assertEqual(self.first.sex, "male")
        else:
            self.assertEqual(self.first.sex, "female")
