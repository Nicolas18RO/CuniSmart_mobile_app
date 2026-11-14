"""R3 E2 — ParentLink API: ownership, reglas de parentesco, pedigree y 409."""

import uuid
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest.mock import patch

from django.utils import timezone
from django.db import close_old_connections
from django.test import TransactionTestCase
from rest_framework.test import APITestCase

from core.models import ParentLink, Rabbit, SyncOperationReceipt
from core.parentlink_replacement import replace_parent_link
from core.tests import _RabbitApiTestCase, _make_verified_user

RABBITS_URL = "/api/rabbits/"


def _parent_url(rabbit_uuid, role):
    return f"{RABBITS_URL}{rabbit_uuid}/parents/{role}/"


def _pedigree_url(rabbit_uuid):
    return f"{RABBITS_URL}{rabbit_uuid}/pedigree/"


class ParentLinkApiTests(_RabbitApiTestCase):
    def setUp(self):
        self.user_a = _make_verified_user(email="parent-a@example.com")
        self.user_b = _make_verified_user(email="parent-b@example.com")
        self.child = self._rabbit(self.user_a.email, name="Cría", sex="female")
        self.sire = self._rabbit(self.user_a.email, name="Padre", sex="male")
        self.dam = self._rabbit(self.user_a.email, name="Madre", sex="female")
        self._auth(self.user_a.email)

    def _rabbit(self, email, **overrides):
        created = self._create_as(email, **overrides)
        return Rabbit.objects.get(uuid=created.data["uuid"])

    def _put(self, child, parent, role, version=None):
        body = {"parent_uuid": str(parent.uuid)}
        if version is not None:
            body["version"] = version
        return self.client.put(
            _parent_url(child.uuid, role),
            body,
            format="json",
        )

    def test_anonymous_cannot_assign_parent(self):
        self._clear_auth()
        response = self._put(self.child, self.sire, "FATHER")
        self.assertEqual(response.status_code, 401)
        self.assertFalse(ParentLink.objects.exists())

    def test_valid_father(self):
        response = self._put(self.child, self.sire, "FATHER")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["role"], "FATHER")
        self.assertEqual(response.data["parent_uuid"], str(self.sire.uuid))
        self.assertEqual(response.data["child_uuid"], str(self.child.uuid))
        self.assertEqual(response.data["version"], 1)
        self.assertIsNone(response.data["deleted_at"])
        self.assertEqual(ParentLink.objects.count(), 1)

    def test_atomic_v2_replacement_replays_historical_receipt(self):
        created = self._put(self.child, self.sire, "FATHER")
        replacement_parent = self._rabbit(self.user_a.email, name="Otro Padre", sex="male")
        old = ParentLink.objects.get(child=self.child, role="FATHER")
        operation = str(uuid.uuid4())
        url = f"{RABBITS_URL}{self.child.uuid}/parents/FATHER/replace/"
        headers = {
            "HTTP_IDEMPOTENCY_KEY": operation,
            "HTTP_X_CUNISMART_SYNC_VERSION": "2",
            "HTTP_X_CUNISMART_SYNC_ACTION": "PARENTLINK_REPLACE",
        }
        body = {"previous": {"cycleUuid": str(old.cycle_uuid), "expectedVersion": old.version},
                "replacement": {"parent_uuid": str(replacement_parent.uuid)}}
        first = self.client.post(url, body, format="json", **headers)
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(ParentLink.objects.filter(child=self.child).count(), 2)
        new = ParentLink.objects.get(child=self.child, deleted_at__isnull=True)
        self.assertNotEqual(old.cycle_uuid, new.cycle_uuid)
        self.assertEqual(SyncOperationReceipt.objects.count(), 1)
        replay = self.client.post(url, body, format="json", **headers)
        self.assertEqual(replay.status_code, 201)
        self.assertEqual(replay.data, first.data)
        self.assertEqual(SyncOperationReceipt.objects.count(), 1)

    def test_v2_conflicting_hash_is_rejected_without_mutation(self):
        self._put(self.child, self.sire, "FATHER")
        replacement_parent = self._rabbit(self.user_a.email, name="Hash Padre", sex="male")
        old = ParentLink.objects.get(child=self.child, role="FATHER")
        operation = str(uuid.uuid4())
        url = f"{RABBITS_URL}{self.child.uuid}/parents/FATHER/replace/"
        headers = {"HTTP_IDEMPOTENCY_KEY": operation,
                   "HTTP_X_CUNISMART_SYNC_VERSION": "2",
                   "HTTP_X_CUNISMART_SYNC_ACTION": "PARENTLINK_REPLACE"}
        body = {"previous": {"cycleUuid": str(old.cycle_uuid), "expectedVersion": old.version},
                "replacement": {"parent_uuid": str(replacement_parent.uuid)}}
        first = self.client.post(url, body, format="json", **headers)
        self.assertEqual(first.status_code, 201)
        changed = {**body, "replacement": {"parent_uuid": str(self.dam.uuid)}}
        conflict = self.client.post(url, changed, format="json", **headers)
        self.assertEqual(conflict.status_code, 409)
        self.assertEqual(ParentLink.objects.filter(child=self.child).count(), 2)

    def test_v2_replacement_does_not_cross_owner(self):
        self._put(self.child, self.sire, "FATHER")
        old = ParentLink.objects.get(child=self.child, role="FATHER")
        self._auth(self.user_b.email)
        other_child = self._rabbit(self.user_b.email, name="Otra", sex="female")
        other_parent = self._rabbit(self.user_b.email, name="Otro", sex="male")
        self._auth(self.user_a.email)
        url = f"{RABBITS_URL}{other_child.uuid}/parents/FATHER/replace/"
        response = self.client.post(url, {
            "previous": {"cycleUuid": str(old.cycle_uuid), "expectedVersion": old.version},
            "replacement": {"parent_uuid": str(other_parent.uuid)},
        }, format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
           HTTP_X_CUNISMART_SYNC_VERSION="2",
           HTTP_X_CUNISMART_SYNC_ACTION="PARENTLINK_REPLACE")
        self.assertIn(response.status_code, (403, 404, 400))

    def _replacement_payload(self, operation):
        old = ParentLink.objects.get(child=self.child, role="FATHER")
        replacement = self._rabbit(self.user_a.email, name="Fallo Padre", sex="male")
        return (old, {
            "previous": {"cycleUuid": str(old.cycle_uuid), "expectedVersion": old.version},
            "replacement": {"parent_uuid": str(replacement.uuid)},
        }, operation)

    def test_v2_rolls_back_when_b_creation_fails(self):
        self._put(self.child, self.sire, "FATHER")
        old, body, operation = self._replacement_payload(str(uuid.uuid4()))
        url = f"{RABBITS_URL}{self.child.uuid}/parents/FATHER/replace/"
        with patch("core.parentlink_replacement.ParentLink.objects.create", side_effect=RuntimeError("inject")):
            with self.assertRaises(RuntimeError):
                self.client.post(url, body, format="json",
                    HTTP_IDEMPOTENCY_KEY=operation,
                    HTTP_X_CUNISMART_SYNC_VERSION="2",
                    HTTP_X_CUNISMART_SYNC_ACTION="PARENTLINK_REPLACE")
        old.refresh_from_db()
        self.assertIsNone(old.deleted_at)
        self.assertEqual(ParentLink.objects.filter(child=self.child).count(), 1)
        self.assertEqual(SyncOperationReceipt.objects.count(), 0)

    def test_v2_rolls_back_before_finalizing_a(self):
        self._put(self.child, self.sire, "FATHER")
        old, body, operation = self._replacement_payload(str(uuid.uuid4()))
        url = f"{RABBITS_URL}{self.child.uuid}/parents/FATHER/replace/"
        with patch.object(ParentLink, "save", side_effect=RuntimeError("inject-before-a")):
            with self.assertRaises(RuntimeError):
                self.client.post(url, body, format="json",
                    HTTP_IDEMPOTENCY_KEY=operation,
                    HTTP_X_CUNISMART_SYNC_VERSION="2",
                    HTTP_X_CUNISMART_SYNC_ACTION="PARENTLINK_REPLACE")
        old.refresh_from_db()
        self.assertIsNone(old.deleted_at)
        self.assertEqual(ParentLink.objects.filter(child=self.child).count(), 1)
        self.assertEqual(SyncOperationReceipt.objects.count(), 0)

    def test_v2_rolls_back_after_b_before_receipt(self):
        self._put(self.child, self.sire, "FATHER")
        old, body, operation = self._replacement_payload(str(uuid.uuid4()))
        url = f"{RABBITS_URL}{self.child.uuid}/parents/FATHER/replace/"
        with patch("django.db.models.query.QuerySet.create", side_effect=RuntimeError("inject-receipt")):
            with self.assertRaises(RuntimeError):
                self.client.post(url, body, format="json",
                    HTTP_IDEMPOTENCY_KEY=operation,
                    HTTP_X_CUNISMART_SYNC_VERSION="2",
                    HTTP_X_CUNISMART_SYNC_ACTION="PARENTLINK_REPLACE")
        old.refresh_from_db()
        self.assertIsNone(old.deleted_at)
        self.assertEqual(ParentLink.objects.filter(child=self.child).count(), 1)
        self.assertEqual(SyncOperationReceipt.objects.count(), 0)

    def test_v2_replay_preserves_a_to_b_after_b_to_c(self):
        self._put(self.child, self.sire, "FATHER")
        b = self._rabbit(self.user_a.email, name="B", sex="male")
        c = self._rabbit(self.user_a.email, name="C", sex="male")
        url = f"{RABBITS_URL}{self.child.uuid}/parents/FATHER/replace/"
        def run(old, parent, operation):
            return self.client.post(url, {
                "previous": {"cycleUuid": str(old.cycle_uuid), "expectedVersion": old.version},
                "replacement": {"parent_uuid": str(parent.uuid)},
            }, format="json", HTTP_IDEMPOTENCY_KEY=operation,
               HTTP_X_CUNISMART_SYNC_VERSION="2",
               HTTP_X_CUNISMART_SYNC_ACTION="PARENTLINK_REPLACE")
        old = ParentLink.objects.get(child=self.child, role="FATHER")
        op_a = str(uuid.uuid4())
        first = run(old, b, op_a)
        self.assertEqual(first.status_code, 201)
        receipt_body = first.data
        current = ParentLink.objects.get(child=self.child, deleted_at__isnull=True)
        op_b = str(uuid.uuid4())
        second = run(current, c, op_b)
        self.assertEqual(second.status_code, 201)
        replay = run(old, b, op_a)
        self.assertEqual(replay.status_code, 201)
        self.assertEqual(replay.data, receipt_body)
        self.assertEqual(ParentLink.objects.filter(child=self.child, deleted_at__isnull=True).get().parent_id, c.pk)

    def test_valid_mother(self):
        response = self._put(self.child, self.dam, "MOTHER")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["role"], "MOTHER")
        self.assertEqual(response.data["parent_uuid"], str(self.dam.uuid))

    def test_female_father_rejected(self):
        response = self._put(self.child, self.dam, "FATHER")
        self.assertEqual(response.status_code, 400)
        self.assertFalse(ParentLink.objects.exists())

    def test_male_mother_rejected(self):
        response = self._put(self.child, self.sire, "MOTHER")
        self.assertEqual(response.status_code, 400)
        self.assertFalse(ParentLink.objects.exists())

    def test_self_parent_rejected(self):
        response = self._put(self.child, self.child, "MOTHER")
        self.assertEqual(response.status_code, 400)
        self.assertFalse(ParentLink.objects.exists())

    def test_same_animal_cannot_be_father_and_mother(self):
        first = self._put(self.child, self.dam, "MOTHER")
        self.assertEqual(first.status_code, 200, first.data)
        response = self._put(self.child, self.dam, "FATHER")
        self.assertEqual(response.status_code, 400)
        self.assertIn("mismo", response.data["detail"].lower())
        self.assertEqual(ParentLink.objects.filter(deleted_at__isnull=True).count(), 1)

    def test_replacing_father_keeps_a_single_active_link(self):
        first = self._put(self.child, self.sire, "FATHER")
        self.assertEqual(first.status_code, 200, first.data)
        other = self._rabbit(self.user_a.email, name="OtroPadre", sex="male")
        self._auth(self.user_a.email)
        response = self._put(self.child, other, "FATHER", version=1)
        self.assertEqual(response.status_code, 200, response.data)
        active = ParentLink.objects.filter(
            child=self.child, role="FATHER", deleted_at__isnull=True
        )
        self.assertEqual(active.count(), 1)
        self.assertEqual(active.get().parent_id, other.id)

    def test_replacing_mother_keeps_a_single_active_link(self):
        first = self._put(self.child, self.dam, "MOTHER")
        self.assertEqual(first.status_code, 200, first.data)
        other = self._rabbit(self.user_a.email, name="OtraMadre", sex="female")
        self._auth(self.user_a.email)
        response = self._put(self.child, other, "MOTHER", version=1)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            ParentLink.objects.filter(
                child=self.child, role="MOTHER", deleted_at__isnull=True
            ).count(),
            1,
        )

    def test_direct_cycle_rejected(self):
        parent = self._rabbit(self.user_a.email, name="Ascendente", sex="male")
        self._auth(self.user_a.email)
        created = self._put(parent, self.child, "MOTHER")
        self.assertEqual(created.status_code, 200, created.data)
        response = self._put(self.child, parent, "FATHER")
        self.assertEqual(response.status_code, 400)

    def test_indirect_cycle_rejected(self):
        mid = self._rabbit(self.user_a.email, name="Medio", sex="male")
        ancestor = self._rabbit(self.user_a.email, name="Abuelo", sex="male")
        self._auth(self.user_a.email)
        self.assertEqual(self._put(mid, self.child, "MOTHER").status_code, 200)
        self.assertEqual(self._put(ancestor, mid, "FATHER").status_code, 200)
        response = self._put(self.child, ancestor, "FATHER")
        self.assertEqual(response.status_code, 400)

    def test_other_owner_parent_is_hidden(self):
        foreign = self._rabbit(self.user_b.email, name="Ajeno", sex="male")
        self._auth(self.user_a.email)
        response = self._put(self.child, foreign, "FATHER")
        self.assertEqual(response.status_code, 404)
        self.assertFalse(ParentLink.objects.exists())

    def test_unknown_parent_uuid(self):
        response = self.client.put(
            _parent_url(self.child.uuid, "FATHER"),
            {"parent_uuid": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"},
            format="json",
        )
        self.assertEqual(response.status_code, 404)

    def test_unknown_child_uuid(self):
        response = self.client.put(
            _parent_url("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "FATHER"),
            {"parent_uuid": str(self.sire.uuid)},
            format="json",
        )
        self.assertEqual(response.status_code, 404)

    def test_deleted_parent_is_not_selectable(self):
        self.sire.deleted_at = timezone.now()
        self.sire.save(update_fields=["deleted_at"])
        response = self._put(self.child, self.sire, "FATHER")
        self.assertEqual(response.status_code, 404)
        self.assertFalse(ParentLink.objects.exists())

    def test_other_owner_cannot_read_pedigree(self):
        created = self._put(self.child, self.sire, "FATHER")
        self.assertEqual(created.status_code, 200, created.data)
        self._auth(self.user_b.email)
        response = self.client.get(_pedigree_url(self.child.uuid))
        self.assertEqual(response.status_code, 404)

    def test_pedigree_lists_parents_and_grandparent(self):
        grandfather = self._rabbit(self.user_a.email, name="AbueloPaterno", sex="male")
        self._auth(self.user_a.email)
        self.assertEqual(self._put(self.sire, grandfather, "FATHER").status_code, 200)
        self.assertEqual(self._put(self.child, self.sire, "FATHER").status_code, 200)
        self.assertEqual(self._put(self.child, self.dam, "MOTHER").status_code, 200)
        response = self.client.get(_pedigree_url(self.child.uuid))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["animal"]["uuid"], str(self.child.uuid))
        self.assertEqual(response.data["animal"]["generation"], 0)
        self.assertEqual(response.data["father"]["uuid"], str(self.sire.uuid))
        self.assertEqual(response.data["father"]["generation"], 1)
        self.assertEqual(response.data["mother"]["uuid"], str(self.dam.uuid))
        generations = {item["uuid"]: item["generation"] for item in response.data["ancestors"]}
        self.assertEqual(generations[str(self.sire.uuid)], 1)
        self.assertEqual(generations[str(self.dam.uuid)], 1)
        self.assertEqual(generations[str(grandfather.uuid)], 2)
        child_pedigree = self.client.get(_pedigree_url(self.sire.uuid))
        descendant_ids = {item["uuid"] for item in child_pedigree.data["descendants"]}
        self.assertIn(str(self.child.uuid), descendant_ids)

    def test_soft_delete_keeps_row_and_frees_role(self):
        created = self._put(self.child, self.sire, "FATHER")
        self.assertEqual(created.status_code, 200, created.data)
        deleted = self.client.delete(
            _parent_url(self.child.uuid, "FATHER"),
            {"version": 1},
            format="json",
        )
        self.assertEqual(deleted.status_code, 200, deleted.data)
        link = ParentLink.objects.get(child=self.child, role="FATHER", parent=self.sire)
        self.assertIsNotNone(link.deleted_at)
        self.assertGreaterEqual(link.version, 2)
        pedigree = self.client.get(_pedigree_url(self.child.uuid))
        self.assertIsNone(pedigree.data["father"])
        other = self._rabbit(self.user_a.email, name="NuevoPadre", sex="male")
        self._auth(self.user_a.email)
        again = self._put(self.child, other, "FATHER")
        self.assertEqual(again.status_code, 200, again.data)
        self.assertEqual(
            ParentLink.objects.filter(
                child=self.child, role="FATHER", deleted_at__isnull=True
            ).count(),
            1,
        )

    def test_stale_version_returns_409(self):
        created = self._put(self.child, self.sire, "FATHER")
        self.assertEqual(created.status_code, 200, created.data)
        other = self._rabbit(self.user_a.email, name="Reemplazo", sex="male")
        self._auth(self.user_a.email)
        updated = self._put(self.child, other, "FATHER", version=1)
        self.assertEqual(updated.status_code, 200, updated.data)
        self.assertEqual(updated.data["version"], 2)
        third = self._rabbit(self.user_a.email, name="Tercero", sex="male")
        self._auth(self.user_a.email)
        stale = self._put(self.child, third, "FATHER", version=1)
        self.assertEqual(stale.status_code, 409)
        self.assertEqual(stale.data.get("code"), "version_conflict")
        self.assertEqual(stale.data["current"]["parent_uuid"], str(other.uuid))
        self.assertEqual(stale.data["current"]["version"], 2)
        active = ParentLink.objects.get(
            child=self.child, role="FATHER", deleted_at__isnull=True
        )
        self.assertEqual(active.parent_id, other.id)
        self.assertEqual(active.version, 2)

    def test_delete_with_stale_version_returns_409(self):
        created = self._put(self.child, self.sire, "FATHER")
        self.assertEqual(created.status_code, 200, created.data)
        other = self._rabbit(self.user_a.email, name="Reemplazo", sex="male")
        self._auth(self.user_a.email)
        self.assertEqual(self._put(self.child, other, "FATHER", version=1).status_code, 200)
        stale = self.client.delete(
            _parent_url(self.child.uuid, "FATHER"),
            {"version": 1},
            format="json",
        )
        self.assertEqual(stale.status_code, 409)
        link = ParentLink.objects.get(
            child=self.child, role="FATHER", deleted_at__isnull=True
        )
        self.assertIsNone(link.deleted_at)


class ParentLinkRouteAuthTests(APITestCase):
    def test_pedigree_requires_authentication(self):
        response = self.client.get(
            _pedigree_url("cccccccc-cccc-4ccc-8ccc-cccccccccccc")
        )
        self.assertEqual(response.status_code, 401)


class ParentLinkConcurrencyTests(TransactionTestCase):
    reset_sequences = True

    def test_two_workers_one_parentlink_replacement(self):
        user = _make_verified_user(email="concurrent@example.com")
        child = Rabbit.objects.create(user=user, name="Child", breed="Rex",
                                      sex="female", birth_date="2024-01-01")
        first = Rabbit.objects.create(user=user, name="First", breed="Rex",
                                      sex="male", birth_date="2024-01-01")
        second = Rabbit.objects.create(user=user, name="Second", breed="Rex",
                                       sex="male", birth_date="2024-01-01")
        from core.genealogy import assign_or_update
        assign_or_update(child=child, parent=first, role="FATHER", version=None)
        old = ParentLink.objects.get(child=child, role="FATHER")
        barrier = Barrier(2)

        def worker(parent, operation):
            close_old_connections()
            try:
                barrier.wait(timeout=10)
                return replace_parent_link(
                    owner=user, child_uuid=child.uuid, role="FATHER",
                    previous_cycle_uuid=old.cycle_uuid,
                    expected_version=old.version, parent_uuid=parent.uuid,
                    operation_uuid=operation,
                )
            except Exception as error:  # one deterministic loser is expected
                return error
            finally:
                close_old_connections()

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(
                lambda args: worker(*args),
                [(second, uuid.uuid4()), (first, uuid.uuid4())],
            ))
        successes = [result for result in results if isinstance(result, SyncOperationReceipt)]
        self.assertEqual(len(successes), 1)
        self.assertEqual(ParentLink.objects.filter(child=child, deleted_at__isnull=True).count(), 1)
        self.assertEqual(SyncOperationReceipt.objects.count(), 1)
