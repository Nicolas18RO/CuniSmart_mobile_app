from datetime import date, timedelta

from django.utils import timezone
from rest_framework.test import APITestCase

from core.models import Rabbit, ReproductiveEvent
from core.tests import _make_verified_user


URL = "/api/reproductive-events/"


class ReproductiveEventApiTests(APITestCase):
    def setUp(self):
        self.owner = _make_verified_user(email="reproduction@example.test")
        self.other = _make_verified_user(email="other-reproduction@example.test")
        self.male = self.rabbit(self.owner, "Macho", "male")
        self.female = self.rabbit(self.owner, "Hembra", "female")
        self.foreign = self.rabbit(self.other, "Ajena", "female")
        self.client.force_authenticate(self.owner)

    def rabbit(self, owner, name, sex, **values):
        return Rabbit.objects.create(
            user=owner, name=name, breed="test", sex=sex,
            birth_date="2025-01-01", **values,
        )

    def body(self, **overrides):
        data = {
            "male_uuid": str(self.male.uuid),
            "female_uuid": str(self.female.uuid),
            "mating_date": "2026-10-01",
            "notes": "observación opcional",
        }
        data.update(overrides)
        return data

    def create_event(self, **overrides):
        response = self.client.post(URL, self.body(**overrides), format="json")
        self.assertEqual(response.status_code, 201, response.data)
        return response

    def test_authentication_create_and_server_calculation(self):
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get(URL).status_code, 401)
        self.client.force_authenticate(self.owner)
        response = self.create_event(estimated_birth_date="2040-01-01")
        self.assertEqual(response.data["estimated_birth_date"], "2026-11-01")
        self.assertEqual(response.data["version"], 1)
        self.assertEqual(response.data["notes"], "observación opcional")
        self.assertEqual(response.data["kinship_evaluation"]["status"], "NO_CALCULABLE")
        self.assertIsNone(response.data["kinship_evaluation"]["expectedInbreeding"])

    def test_update_recalculates_and_version_conflicts(self):
        created = self.create_event()
        detail = f"{URL}{created.data['uuid']}/"
        changed = self.client.patch(detail, {
            "mating_date": "2026-12-15", "notes": "cambio", "version": 1,
        }, format="json")
        self.assertEqual(changed.status_code, 200, changed.data)
        self.assertEqual(changed.data["estimated_birth_date"], "2027-01-15")
        self.assertEqual(changed.data["version"], 2)
        stale = self.client.patch(detail, {"notes": "stale", "version": 1}, format="json")
        self.assertEqual(stale.status_code, 409, stale.data)
        self.assertEqual(stale.data["current"]["version"], 2)
        immutable = self.client.patch(detail, {
            "male_uuid": str(self.male.uuid), "version": 2,
        }, format="json")
        self.assertEqual(immutable.status_code, 400)

    def test_validation_rejects_sex_same_deleted_inactive_and_ownership(self):
        deleted = self.rabbit(self.owner, "Eliminada", "female", deleted_at=timezone.now())
        inactive = self.rabbit(self.owner, "Vendida", "female", status="sold")
        cases = [
            self.body(male_uuid=str(self.female.uuid), female_uuid=str(self.male.uuid)),
            self.body(female_uuid=str(self.male.uuid)),
            self.body(female_uuid=str(deleted.uuid)),
            self.body(female_uuid=str(inactive.uuid)),
            self.body(female_uuid=str(self.foreign.uuid)),
            self.body(mating_date="fecha-inválida"),
        ]
        for payload in cases:
            with self.subTest(payload=payload):
                response = self.client.post(URL, payload, format="json")
                self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(ReproductiveEvent.objects.count(), 0)

    def test_soft_delete_and_owner_isolation(self):
        created = self.create_event()
        detail = f"{URL}{created.data['uuid']}/"
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.get(detail).status_code, 404)
        self.assertEqual(self.client.patch(detail, {"notes": "hack", "version": 1}, format="json").status_code, 404)
        self.client.force_authenticate(self.owner)
        self.assertEqual(self.client.delete(detail, {"version": 1}, format="json").status_code, 204)
        event = ReproductiveEvent.objects.get(uuid=created.data["uuid"])
        self.assertIsNotNone(event.deleted_at)
        self.assertEqual(event.version, 2)
        self.assertEqual(self.client.get(detail).status_code, 404)
        self.assertEqual(self.client.get(URL).data, [])

    def test_active_event_protects_rabbit_sex_and_soft_delete(self):
        self.create_event()
        male_detail = f"/api/rabbits/{self.male.uuid}/"
        sex = self.client.patch(male_detail, {"sex": "female"}, format="json")
        self.assertEqual(sex.status_code, 400, sex.data)
        deleted = self.client.delete(male_detail)
        self.assertEqual(deleted.status_code, 400, deleted.data)
        self.male.refresh_from_db()
        self.assertEqual(self.male.sex, "male")
        self.assertIsNone(self.male.deleted_at)

    def test_calendar_range_states_and_isolation(self):
        today = timezone.localdate()
        dates = [today - timedelta(days=32), today - timedelta(days=31), today - timedelta(days=30)]
        expected = ["OVERDUE", "DUE_TODAY", "UPCOMING"]
        for mating in dates:
            self.create_event(mating_date=mating.isoformat(), notes=mating.isoformat())
        foreign_event = ReproductiveEvent.objects.create(
            user=self.other, male=self.rabbit(self.other, "Otro", "male"),
            female=self.foreign, mating_date=today,
            estimated_birth_date=today + timedelta(days=31),
        )
        response = self.client.get(f"{URL}calendar/", {
            "start_date": (today - timedelta(days=1)).isoformat(),
            "end_date": (today + timedelta(days=1)).isoformat(),
        })
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([row["calendar_state"] for row in response.data["events"]], expected)
        self.assertEqual([row["days_remaining"] for row in response.data["events"]], [-1, 0, 1])
        self.assertNotIn(str(foreign_event.uuid), {row["uuid"] for row in response.data["events"]})
        inverted = self.client.get(f"{URL}calendar/", {"start_date": "2026-02-02", "end_date": "2026-02-01"})
        self.assertEqual(inverted.status_code, 400)
        excessive = self.client.get(f"{URL}calendar/", {"start_date": "2026-01-01", "end_date": "2027-01-03"})
        self.assertEqual(excessive.status_code, 400)
