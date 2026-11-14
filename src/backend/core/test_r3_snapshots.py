from uuid import uuid4

from django.test import TestCase
from rest_framework.test import APIClient

from .genealogy import assign_or_update, clear_parent
from .models import ParentLink, Rabbit, ReproductiveEvent, SyncOperationReceipt
from .tests import _make_verified_user


class R3SnapshotTests(TestCase):
    route = "/api/r3/v1/snapshots/"

    def setUp(self):
        self.owner = _make_verified_user(email="e74-owner@example.test")
        self.other = _make_verified_user(email="e74-other@example.test")
        self.api = APIClient()
        self.api.force_authenticate(self.owner)
        self.child = self.rabbit("female")
        self.parent = self.rabbit("male")

    def rabbit(self, sex):
        return Rabbit.objects.create(user=self.owner, name=sex, sex=sex,
                                     breed="Rex", birth_date="2025-01-01")

    def open(self, **scope):
        response = self.api.post(self.route, scope, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        return response.data

    def test_cycles_tombstones_and_stable_pagination(self):
        link = assign_or_update(child=self.child, parent=self.parent, role="FATHER", version=None)
        tombstone = clear_parent(child=self.child, role="FATHER", version=link.version)
        newer = assign_or_update(child=self.child, parent=self.parent, role="FATHER", version=None)
        self.assertNotEqual(link.cycle_uuid, newer.cycle_uuid)
        self.assertEqual(tombstone.cycle_uuid, link.cycle_uuid)
        first = self.open(entity="PARENT_LINK", page_size=1, children=[str(self.child.uuid)])
        self.assertEqual(first["total"], 2)
        self.assertEqual(first["items"][0]["cycle_uuid"], str(link.cycle_uuid))
        self.assertIsNotNone(first["items"][0]["deleted_at"])
        clear_parent(child=self.child, role="FATHER", version=newer.version)
        page = f"{self.route}{first['snapshot_uuid']}/"
        last = self.api.get(page, {"cursor": 1})
        self.assertEqual(last.status_code, 200)
        self.assertIsNone(last.data["items"][0]["deleted_at"])
        self.assertEqual(last.data["items"][0]["cycle_uuid"], str(newer.cycle_uuid))
        self.assertIsNone(last.data["next_cursor"])
        self.assertEqual(self.api.get(page, {"cursor": 1}).data, last.data)
        self.assertEqual(self.api.get(page, {"cursor": 2}).status_code, 400)
        self.api.force_authenticate(self.other)
        self.assertEqual(self.api.get(page, {"cursor": 1}).status_code, 404)
        self.assertFalse(SyncOperationReceipt.objects.exists())

    def test_unresolved_history_and_empty_scope(self):
        ParentLink.objects.create(child=self.child, parent=self.parent, role="FATHER",
                                  cycle_uuid=None, version=8)
        first = self.open(entity="PARENT_LINK")
        self.assertEqual(first["items"][0]["identity_status"], "UNRESOLVED")
        self.assertIsNone(first["items"][0]["creation_version"])
        empty = self.open(entity="PARENT_LINK", children=[str(uuid4())])
        self.assertEqual((empty["total"], empty["pages"], empty["next_cursor"]), (0, 1, None))

    def test_event_scope_includes_explicit_tombstones(self):
        from django.utils import timezone
        event = ReproductiveEvent.objects.create(
            user=self.owner, male=self.parent, female=self.child,
            mating_date="2026-11-13", estimated_birth_date="2026-12-14", notes="",
            version=2, deleted_at=timezone.now(),
        )
        first = self.open(entity="REPRODUCTIVE_EVENT", **{"from": "2026-11-13", "to": "2026-11-13"})
        self.assertEqual(first["items"][0]["uuid"], str(event.uuid))
        self.assertIsNotNone(first["items"][0]["deleted_at"])
        self.assertEqual(self.open(entity="REPRODUCTIVE_EVENT", **{"from": "2026-11-14"})["total"], 0)
