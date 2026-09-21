"""G10.2 — contrato TDD de credenciales de dispositivo (opción C).

Login biométrico = clave pública enrolada + challenge de un solo uso + firma.
NO implementa el modelo ni las vistas: estos tests deben fallar (404) hasta G10.3.

El flag UserSettings.biometric_enabled NO es una credencial y NO emite JWT.
Nunca viaja huella ni contraseña.
"""

from __future__ import annotations

import base64
from datetime import timedelta

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase
from unittest.mock import patch

from accounts.tests import _make_user

ENROLL_URL = "/api/auth/device-credentials/"
CHALLENGE_URL = "/api/auth/device-credentials/challenge/"
LOGIN_URL = "/api/auth/device-credentials/login/"


def _json(response):
    try:
        return response.json()
    except Exception:
        return {}


def _rsa_keypair():
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_pem = (
        private.public_key()
        .public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        .decode()
    )

    def sign(nonce: str) -> str:
        signature = private.sign(
            nonce.encode("utf-8"),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
        return base64.b64encode(signature).decode("ascii")

    return public_pem, sign


@override_settings(
    EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
)
class DeviceCredentialContractTests(APITestCase):
    """Contrato HTTP de enrolamiento / challenge / login / revocación."""

    def _login(
        self,
        *,
        email="device@example.com",
        password="password1",
        verified=True,
    ):
        _make_user(email=email, password=password, verified=verified)
        response = self.client.post(
            "/api/auth/login/",
            {"email": email, "password": password},
            format="json",
        )
        if verified:
            self.assertEqual(response.status_code, 200)
            return response.data["access"], response.data["refresh"]
        return None, None

    def _enroll(self, access, public_key, device_label="Pixel-test"):
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        return self.client.post(
            ENROLL_URL,
            {"public_key": public_key, "device_label": device_label},
            format="json",
        )

    def _enroll_id(self, access, public_key, device_label="Pixel-test"):
        response = self._enroll(access, public_key, device_label)
        self.assertEqual(response.status_code, 201)
        credential_id = _json(response).get("id")
        self.assertTrue(credential_id)
        return credential_id

    def test_enroll_requires_authentication(self):
        public_key, _ = _rsa_keypair()
        response = self.client.post(
            ENROLL_URL,
            {"public_key": public_key, "device_label": "anon"},
            format="json",
        )
        self.assertEqual(response.status_code, 401)
        self.assertNotIn("id", _json(response))

    def test_enroll_authenticated_returns_id_and_never_echoes_secrets(self):
        access, _ = self._login()
        public_key, _ = _rsa_keypair()
        response = self._enroll(access, public_key)

        self.assertEqual(response.status_code, 201)
        body = _json(response)
        self.assertTrue(body.get("id"))
        self.assertTrue(body.get("created_at"))
        self.assertNotIn("private_key", body)
        self.assertNotIn("fingerprint", body)
        self.assertNotIn("password", body)

    def test_enroll_body_is_public_key_not_biometric_samples(self):
        access, _ = self._login(email="samples@example.com")
        public_key, _ = _rsa_keypair()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        response = self.client.post(
            ENROLL_URL,
            {
                "public_key": public_key,
                "device_label": "lab",
                "fingerprint": "SHOULD-NEVER-BE-ACCEPTED",
                "password": "password1",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertNotIn("id", _json(response))

    def test_challenge_returns_single_use_nonce(self):
        access, _ = self._login(email="chal@example.com")
        public_key, _ = _rsa_keypair()
        credential_id = self._enroll_id(access, public_key)
        self.client.credentials()

        response = self.client.post(
            CHALLENGE_URL,
            {"credential_id": credential_id},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        body = _json(response)
        self.assertTrue(body.get("nonce"))
        self.assertTrue(body.get("expires_at"))
        self.assertNotEqual(body["nonce"], credential_id)

    def test_valid_signature_returns_same_jwt_shape_as_password_login(self):
        access, _ = self._login(email="okbio@example.com")
        public_key, sign = _rsa_keypair()
        credential_id = self._enroll_id(access, public_key)
        self.client.credentials()

        challenge = self.client.post(
            CHALLENGE_URL,
            {"credential_id": credential_id},
            format="json",
        )
        nonce = _json(challenge).get("nonce")
        self.assertTrue(nonce)
        login = self.client.post(
            LOGIN_URL,
            {
                "credential_id": credential_id,
                "nonce": nonce,
                "signature": sign(nonce),
            },
            format="json",
        )
        self.assertEqual(login.status_code, 200)
        body = _json(login)
        self.assertTrue(body.get("access"))
        self.assertTrue(body.get("refresh"))
        self.assertNotEqual(body["access"], access)

    def test_invalid_signature_is_rejected(self):
        access, _ = self._login(email="badsig@example.com")
        public_key, _ = _rsa_keypair()
        credential_id = self._enroll_id(access, public_key)
        self.client.credentials()
        challenge = self.client.post(
            CHALLENGE_URL,
            {"credential_id": credential_id},
            format="json",
        )
        login = self.client.post(
            LOGIN_URL,
            {
                "credential_id": credential_id,
                "nonce": _json(challenge).get("nonce") or "nonce",
                "signature": base64.b64encode(b"not-a-real-signature").decode(),
            },
            format="json",
        )
        self.assertEqual(login.status_code, 400)
        self.assertEqual(_json(login).get("code"), "invalid_signature")
        self.assertNotIn("access", _json(login))

    def test_replayed_nonce_is_rejected(self):
        access, _ = self._login(email="replay@example.com")
        public_key, sign = _rsa_keypair()
        credential_id = self._enroll_id(access, public_key)
        self.client.credentials()
        challenge = self.client.post(
            CHALLENGE_URL,
            {"credential_id": credential_id},
            format="json",
        )
        nonce = _json(challenge).get("nonce")
        self.assertTrue(nonce)
        payload = {
            "credential_id": credential_id,
            "nonce": nonce,
            "signature": sign(nonce),
        }
        first = self.client.post(LOGIN_URL, payload, format="json")
        self.assertEqual(first.status_code, 200)
        second = self.client.post(LOGIN_URL, payload, format="json")
        self.assertEqual(second.status_code, 400)
        self.assertIn(
            _json(second).get("code"),
            ("invalid_signature", "challenge_expired"),
        )
        self.assertNotIn("access", _json(second))

    def test_expired_challenge_is_rejected(self):
        access, _ = self._login(email="expired@example.com")
        public_key, sign = _rsa_keypair()
        credential_id = self._enroll_id(access, public_key)
        self.client.credentials()
        challenge = self.client.post(
            CHALLENGE_URL,
            {"credential_id": credential_id},
            format="json",
        )
        nonce = _json(challenge).get("nonce")
        self.assertTrue(nonce)
        future = timezone.now() + timedelta(minutes=5)
        with patch("django.utils.timezone.now", return_value=future):
            login = self.client.post(
                LOGIN_URL,
                {
                    "credential_id": credential_id,
                    "nonce": nonce,
                    "signature": sign(nonce),
                },
                format="json",
            )
        self.assertEqual(login.status_code, 400)
        self.assertEqual(_json(login).get("code"), "challenge_expired")
        self.assertNotIn("access", _json(login))

    def test_revoked_credential_cannot_login(self):
        access, _ = self._login(email="revoke@example.com")
        public_key, sign = _rsa_keypair()
        credential_id = self._enroll_id(access, public_key)
        deleted = self.client.delete(f"{ENROLL_URL}{credential_id}/")
        self.assertEqual(deleted.status_code, 204)
        self.client.credentials()

        challenge = self.client.post(
            CHALLENGE_URL,
            {"credential_id": credential_id},
            format="json",
        )
        nonce = _json(challenge).get("nonce") or "nonce"
        login = self.client.post(
            LOGIN_URL,
            {
                "credential_id": credential_id,
                "nonce": nonce,
                "signature": sign(nonce),
            },
            format="json",
        )
        self.assertEqual(login.status_code, 400)
        self.assertEqual(_json(login).get("code"), "credential_revoked")
        self.assertNotIn("access", _json(login))

    def test_biometric_enabled_flag_does_not_issue_jwt(self):
        access, _ = self._login(email="flagonly@example.com")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        put = self.client.put(
            "/api/users/biometric-status/",
            {"biometric_enabled": True},
            format="json",
        )
        self.assertEqual(put.status_code, 200)
        self.client.credentials()

        login = self.client.post(
            LOGIN_URL,
            {
                "credential_id": "not-enrolled",
                "nonce": "n",
                "signature": "s",
            },
            format="json",
        )
        self.assertNotEqual(login.status_code, 200)
        self.assertNotIn("access", _json(login))
        self.assertNotIn("refresh", _json(login))

    def test_logout_keeps_enrollment_and_allows_later_biometric_login(self):
        """Decisión G10.1-B: logout invalida JWT, no borra la credencial."""
        access, refresh = self._login(email="keep@example.com")
        public_key, sign = _rsa_keypair()
        credential_id = self._enroll_id(access, public_key)

        logout = self.client.post(
            "/api/auth/logout/",
            {"refresh": refresh},
            format="json",
        )
        self.assertEqual(logout.status_code, 204)
        self.client.credentials()

        challenge = self.client.post(
            CHALLENGE_URL,
            {"credential_id": credential_id},
            format="json",
        )
        self.assertEqual(challenge.status_code, 200)
        nonce = _json(challenge).get("nonce")
        self.assertTrue(nonce)
        login = self.client.post(
            LOGIN_URL,
            {
                "credential_id": credential_id,
                "nonce": nonce,
                "signature": sign(nonce),
            },
            format="json",
        )
        self.assertEqual(login.status_code, 200)
        self.assertTrue(_json(login).get("access"))
        self.assertTrue(_json(login).get("refresh"))

    def test_foreign_key_cannot_authenticate_as_another_user(self):
        access_a, _ = self._login(email="alice@example.com")
        public_a, _ = _rsa_keypair()
        credential_a = self._enroll_id(access_a, public_a)

        access_b, _ = self._login(email="bob@example.com")
        public_b, sign_b = _rsa_keypair()
        self._enroll(access_b, public_b)
        self.client.credentials()

        challenge = self.client.post(
            CHALLENGE_URL,
            {"credential_id": credential_a},
            format="json",
        )
        nonce = _json(challenge).get("nonce") or "nonce"
        login = self.client.post(
            LOGIN_URL,
            {
                "credential_id": credential_a,
                "nonce": nonce,
                "signature": sign_b(nonce),
            },
            format="json",
        )
        self.assertEqual(login.status_code, 400)
        self.assertEqual(_json(login).get("code"), "invalid_signature")
        self.assertNotIn("access", _json(login))

    def test_unverified_user_cannot_complete_biometric_login(self):
        user = _make_user(
            email="pending-bio@example.com",
            password="password1",
            verified=True,
        )
        login_pw = self.client.post(
            "/api/auth/login/",
            {"email": user.email, "password": "password1"},
            format="json",
        )
        access = login_pw.data["access"]
        public_key, sign = _rsa_keypair()
        credential_id = self._enroll_id(access, public_key)
        user.is_verified = False
        user.save(update_fields=["is_verified"])
        self.client.credentials()

        challenge = self.client.post(
            CHALLENGE_URL,
            {"credential_id": credential_id},
            format="json",
        )
        nonce = _json(challenge).get("nonce") or "nonce"
        bio = self.client.post(
            LOGIN_URL,
            {
                "credential_id": credential_id,
                "nonce": nonce,
                "signature": sign(nonce),
            },
            format="json",
        )
        self.assertEqual(bio.status_code, 400)
        self.assertEqual(_json(bio).get("code"), "email_not_verified")
        self.assertNotIn("access", _json(bio))

    def test_revoke_requires_authentication(self):
        response = self.client.delete(f"{ENROLL_URL}some-id/")
        self.assertEqual(response.status_code, 401)
