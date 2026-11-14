import base64
import json
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest.mock import patch
from uuid import uuid4

from django.db import IntegrityError, connection, connections
from django.test import TransactionTestCase
from rest_framework.test import APIClient

from .models import Rabbit, ReproductiveEvent, SyncOperationReceipt
from .tests import _make_verified_user


class R3SyncHttpTests(TransactionTestCase):
    def setUp(self):
        self.owner = _make_verified_user(email="r3-http@example.test")
        self.client.force_login(self.owner)
        self.api = APIClient()
        self.api.force_authenticate(self.owner)
        self.male = self.rabbit("male")
        self.female = self.rabbit("female")
        self.events = "/api/reproductive-events/"
        self.parent = f"/api/rabbits/{self.female.uuid}/parents/FATHER/"
        self.payload = {"male_uuid": str(self.male.uuid), "female_uuid": str(self.female.uuid),
                        "mating_date": "2026-11-13"}

    def rabbit(self, sex, owner=None):
        return Rabbit.objects.create(user=owner or self.owner, name=sex, breed="Rex",
                                     sex=sex, birth_date="2025-01-01")

    def send(self, method, route, payload, action, key=None, api=None):
        return getattr(api or self.api, method)(
            route, payload, format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid4()),
            HTTP_X_CUNISMART_SYNC_VERSION="1",
            HTTP_X_CUNISMART_SYNC_ACTION=action,
        )

    def receipt(self, response):
        return json.loads(base64.urlsafe_b64decode(response["X-CuniSmart-Sync-Receipt"]))

    def test_parent_lifecycle_replay_and_stale_version(self):
        key = uuid4()
        data = {"parent_uuid": str(self.male.uuid)}
        created = self.send("put", self.parent, data, "CREATE", key)
        self.assertEqual(created.status_code, 200, created.data)
        identity = self.receipt(created)["remoteIdentity"]
        self.assertEqual((identity["childUuid"], identity["role"]),
                         (str(self.female.uuid), "FATHER"))
        self.assertEqual(identity["creationVersion"], created.data["version"])
        self.assertEqual(identity["cycleUuid"], str(
            self.female.parent_links.get(role="FATHER").cycle_uuid
        ))
        version = created.data["version"]
        updated = self.send("put", self.parent, {**data, "version": version}, "UPDATE")
        self.assertEqual(updated.status_code, 200, updated.data)
        stale = self.send("put", self.parent, {**data, "version": version}, "UPDATE")
        self.assertEqual((stale.status_code, stale.data["code"]), (409, "version_conflict"))
        delete_key = uuid4()
        delete = {"version": updated.data["version"]}
        removed = self.send("delete", self.parent, delete, "DELETE", delete_key)
        self.assertEqual(removed.status_code, 200)
        self.assertEqual(self.receipt(self.send("delete", self.parent, delete, "DELETE",
                                               delete_key)), self.receipt(removed))
        historical = self.send("put", self.parent, data, "CREATE", key)
        self.assertEqual(historical.data, created.data)
        self.assertEqual(self.receipt(historical), self.receipt(created))

    def test_event_lifecycle_204_and_changed_hash(self):
        key = uuid4()
        first = self.send("post", self.events, self.payload, "CREATE", key)
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(self.send("post", self.events, self.payload, "CREATE", key).data,
                         first.data)
        bad = self.send("post", self.events, {**self.payload, "notes": "different"}, "CREATE", key)
        self.assertEqual((bad.status_code, bad.data["code"]), (409, "idempotency_key_conflict"))
        route = f"{self.events}{first.data['uuid']}/"
        updated = self.send("patch", route, {"version": 1, "notes": "Cría"}, "UPDATE")
        self.assertEqual(updated.status_code, 200, updated.data)
        delete_key = uuid4()
        for _ in range(2):
            deleted = self.send("delete", route, {"version": 2}, "DELETE", delete_key)
            self.assertEqual((deleted.status_code, deleted.content), (204, b""))
            self.assertEqual(self.receipt(deleted)["remoteVersion"], 3)
        self.assertEqual(ReproductiveEvent.objects.count(), 1)

    def test_legacy_and_owner_isolation(self):
        old = self.api.post(self.events, self.payload, format="json")
        self.assertEqual(old.status_code, 201)
        self.assertNotIn("X-CuniSmart-Sync-Receipt", old)
        key = uuid4()
        first = self.send("post", self.events, self.payload, "CREATE", key)
        other = _make_verified_user(email="r3-http-other@example.test")
        api = APIClient()
        api.force_authenticate(other)
        rejected = self.send("post", self.events, self.payload, "CREATE", key, api)
        self.assertEqual(rejected.status_code, 400)
        second = self.send("post", self.events, {
            **self.payload, "male_uuid": str(self.rabbit("male", other).uuid),
            "female_uuid": str(self.rabbit("female", other).uuid),
        }, "CREATE", key, api)
        self.assertEqual(second.status_code, 201)
        self.assertNotEqual(self.receipt(first)["receiptId"], self.receipt(second)["receiptId"])

    def test_rollback_and_concurrent_replay(self):
        with patch.object(SyncOperationReceipt.objects, "create", side_effect=IntegrityError):
            with self.assertRaises(IntegrityError):
                self.send("post", self.events, self.payload, "CREATE")
        self.assertFalse(ReproductiveEvent.objects.exists())
        self.assertFalse(SyncOperationReceipt.objects.exists())
        invalid = self.send("post", self.events, {**self.payload,
                            "female_uuid": self.payload["male_uuid"]}, "CREATE")
        self.assertEqual(invalid.status_code, 400)
        self.assertFalse(SyncOperationReceipt.objects.exists())
        self.assertEqual(connection.vendor, "postgresql")
        barrier, key = Barrier(2), uuid4()

        def send():
            api = APIClient()
            api.force_authenticate(self.owner)
            try:
                barrier.wait(timeout=10)
                response = self.send("post", self.events, self.payload, "CREATE", key, api)
                return response.status_code, self.receipt(response)
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=2) as pool:
            one, two = [pool.submit(send) for _ in range(2)]
            self.assertEqual(one.result(timeout=30), two.result(timeout=30))
        self.assertEqual(ReproductiveEvent.objects.count(), 1)
        self.assertEqual(SyncOperationReceipt.objects.count(), 1)
