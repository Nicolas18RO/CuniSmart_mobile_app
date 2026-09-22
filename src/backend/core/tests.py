"""R2.1 ownership + R2.2 identidad (UUID / version / deleted_at).

El cliente no elige el propietario. request.user es la única fuente.
El UUID es la identidad externa; el id entero permanece interno.
"""

import uuid

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APITestCase

from core.models import Rabbit

User = get_user_model()

RABBITS_URL = "/api/rabbits/"


def _payload(**overrides):
    body = {
        "name": "Luna",
        "breed": "Rex",
        "sex": "female",
        "birth_date": "2024-01-15",
        "status": "active",
        "notes": "",
    }
    body.update(overrides)
    return body


def _make_verified_user(*, email, password="password1"):
    return User.objects.create_user(
        email=email,
        password=password,
        is_verified=True,
        is_active=True,
    )


class _RabbitApiTestCase(APITestCase):
    def _access_token(self, email, password="password1"):
        response = self.client.post(
            "/api/auth/login/",
            {"email": email, "password": password},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        return response.data["access"]

    def _auth(self, email, password="password1"):
        token = self._access_token(email, password)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        return token

    def _clear_auth(self):
        self.client.credentials()

    def _create_as(self, email, **overrides):
        self._auth(email)
        response = self.client.post(RABBITS_URL, _payload(**overrides), format="json")
        self.assertEqual(response.status_code, 201, response.data)
        return response


class RabbitAnonymousAuthenticationTests(_RabbitApiTestCase):
    def setUp(self):
        self.owner = _make_verified_user(email="owner-r21@example.com")
        self._create_as(self.owner.email, name="Nube")
        self.rabbit_id = Rabbit.objects.get(name="Nube").pk
        self.detail = f"{RABBITS_URL}{self.rabbit_id}/"
        self._clear_auth()

    def test_anonymous_cannot_list_rabbits(self):
        response = self.client.get(RABBITS_URL)
        self.assertEqual(response.status_code, 401)

    def test_anonymous_cannot_create_rabbits(self):
        response = self.client.post(RABBITS_URL, _payload(), format="json")
        self.assertEqual(response.status_code, 401)
        self.assertFalse(Rabbit.objects.filter(name="Luna").exists())

    def test_anonymous_cannot_retrieve_rabbits(self):
        response = self.client.get(self.detail)
        self.assertEqual(response.status_code, 401)

    def test_anonymous_cannot_update_rabbits(self):
        response = self.client.put(
            self.detail,
            _payload(name="Nube", breed="Rex"),
            format="json",
        )
        self.assertEqual(response.status_code, 401)
        response = self.client.patch(self.detail, {"notes": "hack"}, format="json")
        self.assertEqual(response.status_code, 401)

    def test_anonymous_cannot_delete_rabbits(self):
        response = self.client.delete(self.detail)
        self.assertEqual(response.status_code, 401)
        self.assertTrue(Rabbit.objects.filter(pk=self.rabbit_id).exists())


class RabbitOwnershipTests(_RabbitApiTestCase):
    def setUp(self):
        self.user_a = _make_verified_user(email="user-a-r21@example.com")
        self.user_b = _make_verified_user(email="user-b-r21@example.com")
        created = self._create_as(self.user_a.email, name="ConejoA")
        self.rabbit_a_id = created.data["id"]
        self.detail_a = f"{RABBITS_URL}{self.rabbit_a_id}/"

    def test_user_a_can_retrieve_own_rabbit(self):
        self._auth(self.user_a.email)
        response = self.client.get(self.detail_a)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["id"], self.rabbit_a_id)
        self.assertEqual(response.data["name"], "ConejoA")

    def test_user_a_list_contains_only_own_rabbits(self):
        self._create_as(self.user_b.email, name="ConejoB")
        self._auth(self.user_a.email)
        response = self.client.get(RABBITS_URL)
        self.assertEqual(response.status_code, 200)
        names = {row["name"] for row in response.data}
        self.assertIn("ConejoA", names)
        self.assertNotIn("ConejoB", names)

    def test_user_b_cannot_retrieve_user_a_rabbit(self):
        self._auth(self.user_b.email)
        response = self.client.get(self.detail_a)
        self.assertEqual(response.status_code, 404)

    def test_user_b_cannot_update_user_a_rabbit(self):
        self._auth(self.user_b.email)
        put_response = self.client.put(
            self.detail_a,
            _payload(name="Hijacked", breed="Rex"),
            format="json",
        )
        self.assertEqual(put_response.status_code, 404)
        patch_response = self.client.patch(
            self.detail_a,
            {"name": "Hijacked"},
            format="json",
        )
        self.assertEqual(patch_response.status_code, 404)
        rabbit = Rabbit.objects.get(pk=self.rabbit_a_id)
        self.assertEqual(rabbit.name, "ConejoA")
        self.assertEqual(rabbit.user_id, self.user_a.id)

    def test_user_b_cannot_delete_user_a_rabbit(self):
        self._auth(self.user_b.email)
        response = self.client.delete(self.detail_a)
        self.assertEqual(response.status_code, 404)
        self.assertTrue(Rabbit.objects.filter(pk=self.rabbit_a_id).exists())

    def test_user_a_can_update_own_rabbit(self):
        self._auth(self.user_a.email)
        response = self.client.patch(
            self.detail_a,
            {"notes": "actualizado por A"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        rabbit = Rabbit.objects.get(pk=self.rabbit_a_id)
        self.assertEqual(rabbit.notes, "actualizado por A")
        self.assertEqual(rabbit.user_id, self.user_a.id)

    def test_user_a_can_delete_own_rabbit(self):
        self._auth(self.user_a.email)
        response = self.client.delete(self.detail_a)
        self.assertEqual(response.status_code, 204)
        rabbit = Rabbit.objects.get(pk=self.rabbit_a_id)
        self.assertIsNotNone(rabbit.deleted_at)
        list_response = self.client.get(RABBITS_URL)
        names = {row["name"] for row in list_response.data}
        self.assertNotIn("ConejoA", names)


class RabbitCreateAssignsRequestUserTests(_RabbitApiTestCase):
    def setUp(self):
        self.user_a = _make_verified_user(email="create-a-r21@example.com")
        self.user_b = _make_verified_user(email="create-b-r21@example.com")

    def test_authenticated_create_assigns_request_user(self):
        response = self._create_as(self.user_a.email, name="Propio")
        rabbit = Rabbit.objects.get(pk=response.data["id"])
        self.assertEqual(rabbit.user_id, self.user_a.id)
        self.assertNotEqual(rabbit.user_id, self.user_b.id)

    def test_client_cannot_assign_another_user_as_owner(self):
        self._auth(self.user_a.email)
        response = self.client.post(
            RABBITS_URL,
            _payload(
                name="Usurpado",
                user=self.user_b.id,
                user_id=self.user_b.id,
            ),
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        rabbit = Rabbit.objects.get(pk=response.data["id"])
        self.assertEqual(rabbit.user_id, self.user_a.id)
        self.assertNotEqual(rabbit.user_id, self.user_b.id)
        if "user" in response.data:
            self.assertEqual(response.data["user"], self.user_a.id)


class RabbitIdentityTests(_RabbitApiTestCase):
    def setUp(self):
        self.user_a = _make_verified_user(email="ident-a-r22@example.com")
        self.user_b = _make_verified_user(email="ident-b-r22@example.com")

    def test_create_without_uuid_assigns_stable_uuid_and_version_one(self):
        response = self._create_as(self.user_a.email, name="SinUuid")
        self.assertIn("uuid", response.data)
        assigned = uuid.UUID(str(response.data["uuid"]))
        rabbit = Rabbit.objects.get(pk=response.data["id"])
        self.assertEqual(rabbit.uuid, assigned)
        self.assertEqual(rabbit.version, 1)
        self.assertIsNone(rabbit.deleted_at)
        self.assertEqual(response.data["version"], 1)
        self.assertIsNone(response.data["deleted_at"])

    def test_client_can_supply_uuid_on_create(self):
        client_uuid = uuid.uuid4()
        response = self._create_as(
            self.user_a.email,
            name="ConUuid",
            uuid=str(client_uuid),
        )
        self.assertEqual(response.status_code, 201)
        rabbit = Rabbit.objects.get(pk=response.data["id"])
        self.assertEqual(rabbit.uuid, client_uuid)
        self.assertEqual(str(response.data["uuid"]), str(client_uuid))

    def test_uuid_must_be_globally_unique(self):
        shared = uuid.uuid4()
        self._create_as(self.user_a.email, name="Primero", uuid=str(shared))
        self._auth(self.user_b.email)
        response = self.client.post(
            RABBITS_URL,
            _payload(name="Duplicado", uuid=str(shared)),
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertFalse(Rabbit.objects.filter(name="Duplicado").exists())

    def test_detail_can_be_retrieved_by_uuid(self):
        created = self._create_as(self.user_a.email, name="FichaUuid")
        rabbit_uuid = created.data["uuid"]
        self._auth(self.user_a.email)
        response = self.client.get(f"{RABBITS_URL}{rabbit_uuid}/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["id"], created.data["id"])
        self.assertEqual(str(response.data["uuid"]), str(rabbit_uuid))
        self.assertEqual(response.data["name"], "FichaUuid")

    def test_user_b_cannot_retrieve_user_a_rabbit_by_uuid(self):
        created = self._create_as(self.user_a.email, name="PrivadoUuid")
        self._auth(self.user_b.email)
        response = self.client.get(f"{RABBITS_URL}{created.data['uuid']}/")
        self.assertEqual(response.status_code, 404)

    def test_uuid_cannot_be_changed_after_create(self):
        created = self._create_as(self.user_a.email, name="Inmutable")
        original = created.data["uuid"]
        self._auth(self.user_a.email)
        response = self.client.patch(
            f"{RABBITS_URL}{original}/",
            {"uuid": str(uuid.uuid4())},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        rabbit = Rabbit.objects.get(pk=created.data["id"])
        self.assertEqual(str(rabbit.uuid), str(original))

    def test_normal_list_excludes_logically_deleted_rows(self):
        created = self._create_as(self.user_a.email, name="Oculto")
        rabbit = Rabbit.objects.get(pk=created.data["id"])
        rabbit.deleted_at = timezone.now()
        rabbit.save(update_fields=["deleted_at"])
        self._auth(self.user_a.email)
        response = self.client.get(RABBITS_URL)
        self.assertEqual(response.status_code, 200)
        names = {row["name"] for row in response.data}
        self.assertNotIn("Oculto", names)
        self.assertTrue(Rabbit.objects.filter(pk=rabbit.pk).exists())


class RabbitSoftDeleteAndFichaContractTests(_RabbitApiTestCase):
    def setUp(self):
        self.user_a = _make_verified_user(email="ficha-a-r23@example.com")
        self.user_b = _make_verified_user(email="ficha-b-r23@example.com")
        created = self._create_as(self.user_a.email, name="Ficha")
        self.rabbit_id = created.data["id"]
        self.rabbit_uuid = created.data["uuid"]
        self.detail_uuid = f"{RABBITS_URL}{self.rabbit_uuid}/"

    def test_delete_sets_deleted_at_and_keeps_row(self):
        self._auth(self.user_a.email)
        response = self.client.delete(self.detail_uuid)
        self.assertEqual(response.status_code, 204)
        rabbit = Rabbit.objects.get(pk=self.rabbit_id)
        self.assertIsNotNone(rabbit.deleted_at)
        self.assertGreaterEqual(rabbit.version, 2)

    def test_deleted_rabbit_is_hidden_from_list_and_detail(self):
        self._auth(self.user_a.email)
        self.client.delete(self.detail_uuid)
        list_response = self.client.get(RABBITS_URL)
        names = {row["name"] for row in list_response.data}
        self.assertNotIn("Ficha", names)
        detail_response = self.client.get(self.detail_uuid)
        self.assertEqual(detail_response.status_code, 404)

    def test_user_b_cannot_soft_delete_user_a_rabbit(self):
        self._auth(self.user_b.email)
        response = self.client.delete(self.detail_uuid)
        self.assertEqual(response.status_code, 404)
        rabbit = Rabbit.objects.get(pk=self.rabbit_id)
        self.assertIsNone(rabbit.deleted_at)

    def test_detail_returns_complete_ficha_fields(self):
        self._auth(self.user_a.email)
        response = self.client.get(self.detail_uuid)
        self.assertEqual(response.status_code, 200)
        for key in (
            "id",
            "uuid",
            "name",
            "breed",
            "sex",
            "birth_date",
            "weight",
            "status",
            "notes",
            "version",
        ):
            self.assertIn(key, response.data)

    def test_negative_weight_is_rejected(self):
        self._auth(self.user_a.email)
        response = self.client.patch(
            self.detail_uuid,
            {"weight": -1},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        rabbit = Rabbit.objects.get(pk=self.rabbit_id)
        self.assertIsNone(rabbit.weight)

    def test_update_increments_version(self):
        self._auth(self.user_a.email)
        response = self.client.patch(
            self.detail_uuid,
            {"notes": "editado"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["version"], 2)
        rabbit = Rabbit.objects.get(pk=self.rabbit_id)
        self.assertEqual(rabbit.version, 2)
        self.assertEqual(rabbit.notes, "editado")

    def test_matching_version_updates_and_increments(self):
        self._auth(self.user_a.email)
        response = self.client.patch(
            self.detail_uuid,
            {"notes": "con version", "version": 1},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["version"], 2)
        self.assertEqual(response.data["notes"], "con version")

    def test_stale_version_returns_409_with_remote_snapshot(self):
        self._auth(self.user_a.email)
        first = self.client.patch(
            self.detail_uuid,
            {"notes": "servidor", "version": 1},
            format="json",
        )
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.data["version"], 2)
        stale = self.client.patch(
            self.detail_uuid,
            {"notes": "telefono", "version": 1},
            format="json",
        )
        self.assertEqual(stale.status_code, 409)
        rabbit = Rabbit.objects.get(pk=self.rabbit_id)
        self.assertEqual(rabbit.notes, "servidor")
        self.assertEqual(rabbit.version, 2)
        self.assertEqual(stale.data.get("code"), "version_conflict")
        current = stale.data.get("current")
        self.assertIsInstance(current, dict)
        self.assertEqual(current["notes"], "servidor")
        self.assertEqual(current["version"], 2)
        self.assertEqual(current["uuid"], self.rabbit_uuid)
