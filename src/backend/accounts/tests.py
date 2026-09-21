"""Auth tests: current behavior (R1.1) plus password reset (R1.2)."""

import re
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core import mail
from django.core.signing import SignatureExpired
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APITestCase
from unittest.mock import patch

from accounts.models import PasswordResetToken
from accounts.serializers import RegisterSerializer
from accounts.services.auth_service import validate_user_login
from accounts.services.email_verification import sign_verification_token, verify_token
from accounts.services.session_service import build_bootstrap_payload

User = get_user_model()


def _make_user(*, email, password="password1", verified=True, active=True):
    return User.objects.create_user(
        email=email,
        password=password,
        is_verified=verified,
        is_active=active,
    )


class ValidateUserLoginTests(TestCase):
    def test_none_is_invalid_credentials(self):
        result = validate_user_login(None)
        self.assertFalse(result.ok)
        self.assertEqual(result.code, "invalid_credentials")

    def test_inactive_user(self):
        user = _make_user(email="inactive@example.com", active=False)
        result = validate_user_login(user)
        self.assertFalse(result.ok)
        self.assertEqual(result.code, "inactive_user")

    def test_unverified_user(self):
        user = _make_user(email="pending@example.com", verified=False)
        result = validate_user_login(user)
        self.assertFalse(result.ok)
        self.assertEqual(result.code, "email_not_verified")

    def test_active_verified_user(self):
        user = _make_user(email="ok@example.com")
        result = validate_user_login(user)
        self.assertTrue(result.ok)
        self.assertIsNone(result.code)


class RegisterSerializerTests(TestCase):
    def test_creates_unverified_user(self):
        ser = RegisterSerializer(
            data={"email": "new@example.com", "password": "password1"}
        )
        self.assertTrue(ser.is_valid(), ser.errors)
        user = ser.save()
        self.assertFalse(user.is_verified)
        self.assertTrue(user.is_active)
        self.assertEqual(user.email, "new@example.com")

    def test_duplicate_email_rejected(self):
        _make_user(email="dup@example.com")
        ser = RegisterSerializer(
            data={"email": "dup@example.com", "password": "password1"}
        )
        self.assertFalse(ser.is_valid())
        self.assertIn("email", ser.errors)

    def test_short_password_rejected(self):
        ser = RegisterSerializer(
            data={"email": "short@example.com", "password": "1234567"}
        )
        self.assertFalse(ser.is_valid())
        self.assertIn("password", ser.errors)


class EmailVerificationTokenTests(TestCase):
    def test_valid_token_returns_user(self):
        user = _make_user(email="verify@example.com", verified=False)
        token = sign_verification_token(user)
        found = verify_token(token)
        self.assertIsNotNone(found)
        self.assertEqual(found.pk, user.pk)

    def test_invalid_signature_returns_none(self):
        self.assertIsNone(verify_token("not-a-real-token"))

    def test_expired_token_returns_none(self):
        user = _make_user(email="expired@example.com", verified=False)
        token = sign_verification_token(user)
        with patch(
            "accounts.services.email_verification.TimestampSigner.unsign",
            side_effect=SignatureExpired("expired"),
        ):
            self.assertIsNone(verify_token(token))


class BootstrapPayloadTests(TestCase):
    def test_anonymous_payload(self):
        payload = build_bootstrap_payload(session_valid=False, user=None)
        self.assertFalse(payload["session_valid"])
        self.assertTrue(payload["auth_required"])
        self.assertFalse(payload["biometric_available"])


@override_settings(
    EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
)
class AuthApiTests(APITestCase):
    def test_bootstrap_anonymous_session_invalid(self):
        response = self.client.get("/api/auth/bootstrap/")
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data["session_valid"])
        self.assertTrue(response.data["auth_required"])

    def test_login_unverified_does_not_return_tokens(self):
        _make_user(email="uv@example.com", password="password1", verified=False)
        response = self.client.post(
            "/api/auth/login/",
            {"email": "uv@example.com", "password": "password1"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertNotIn("access", response.data)
        self.assertNotIn("refresh", response.data)
        self.assertEqual(response.data.get("code"), "email_not_verified")

    def test_login_verified_returns_jwt_pair(self):
        _make_user(email="ok@example.com", password="password1", verified=True)
        response = self.client.post(
            "/api/auth/login/",
            {"email": "ok@example.com", "password": "password1"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data.get("access"))
        self.assertTrue(response.data.get("refresh"))

    def test_verify_email_invalid_token(self):
        response = self.client.get("/api/auth/verify-email/", {"token": "bad"})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data.get("code"), "validation_error")

    def test_verify_email_valid_token_sets_verified(self):
        user = _make_user(email="link@example.com", verified=False)
        token = sign_verification_token(user)
        response = self.client.get("/api/auth/verify-email/", {"token": token})
        self.assertEqual(response.status_code, 200)
        user.refresh_from_db()
        self.assertTrue(user.is_verified)

    def test_register_does_not_echo_verification_token(self):
        response = self.client.post(
            "/api/auth/register/",
            {"email": "newreg@example.com", "password": "password1"},
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertNotIn("debug_verification_link", response.data)
        self.assertNotIn("token", response.data)

    def test_resend_unknown_email_generic_ok(self):
        response = self.client.post(
            "/api/auth/resend-verification/",
            {"email": "nobody@example.com"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("If an account exists", response.data.get("detail", ""))

    def test_resend_unverified_sends_mail(self):
        _make_user(email="needv@example.com", verified=False)
        response = self.client.post(
            "/api/auth/resend-verification/",
            {"email": "needv@example.com"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(mail.outbox), 1)

    def test_register_email_contains_six_digit_code_not_in_json(self):
        response = self.client.post(
            "/api/auth/register/",
            {"email": "otpjson@example.com", "password": "password1"},
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(len(mail.outbox), 1)
        code = _verification_code_from_outbox()
        self.assertRegex(code, r"^\d{6}$")
        self.assertNotIn(code, str(response.data))
        self.assertNotIn("debug_verification_link", response.data)

    def test_verify_email_code_correct_marks_user_verified(self):
        self.client.post(
            "/api/auth/register/",
            {"email": "otpok@example.com", "password": "password1"},
            format="json",
        )
        code = _verification_code_from_outbox()
        response = self.client.post(
            "/api/auth/verify-email-code/",
            {"email": "otpok@example.com", "code": code},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data.get("verified"))
        user = User.objects.get(email="otpok@example.com")
        self.assertTrue(user.is_verified)
        login = self.client.post(
            "/api/auth/login/",
            {"email": "otpok@example.com", "password": "password1"},
            format="json",
        )
        self.assertEqual(login.status_code, 200)

    def test_verify_email_code_wrong_does_not_verify(self):
        self.client.post(
            "/api/auth/register/",
            {"email": "otpbad@example.com", "password": "password1"},
            format="json",
        )
        response = self.client.post(
            "/api/auth/verify-email-code/",
            {"email": "otpbad@example.com", "code": "000000"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data.get("code"), "verification_code_invalid")
        user = User.objects.get(email="otpbad@example.com")
        self.assertFalse(user.is_verified)

    def test_verify_email_code_expired(self):
        from accounts.models import EmailVerificationCode

        self.client.post(
            "/api/auth/register/",
            {"email": "otpexp@example.com", "password": "password1"},
            format="json",
        )
        code = _verification_code_from_outbox()
        EmailVerificationCode.objects.filter(
            user__email="otpexp@example.com"
        ).update(expires_at=timezone.now() - timedelta(seconds=1))
        response = self.client.post(
            "/api/auth/verify-email-code/",
            {"email": "otpexp@example.com", "code": code},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data.get("code"), "verification_code_expired")

    def test_resend_verification_sends_new_six_digit_code(self):
        self.client.post(
            "/api/auth/register/",
            {"email": "otpresend@example.com", "password": "password1"},
            format="json",
        )
        first = _verification_code_from_outbox()
        response = self.client.post(
            "/api/auth/resend-verification/",
            {"email": "otpresend@example.com"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(mail.outbox), 2)
        second = _verification_code_from_outbox()
        self.assertRegex(second, r"^\d{6}$")
        old = self.client.post(
            "/api/auth/verify-email-code/",
            {"email": "otpresend@example.com", "code": first},
            format="json",
        )
        self.assertEqual(old.status_code, 400)
        ok = self.client.post(
            "/api/auth/verify-email-code/",
            {"email": "otpresend@example.com", "code": second},
            format="json",
        )
        self.assertEqual(ok.status_code, 200)

    def test_verify_email_code_unknown_email_is_invalid(self):
        response = self.client.post(
            "/api/auth/verify-email-code/",
            {"email": "ghost@example.com", "code": "123456"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data.get("code"), "verification_code_invalid")


def _verification_code_from_outbox() -> str:
    body = mail.outbox[-1].body
    match = re.search(r"Codigo:\s*(\d{6})", body)
    if match is None:
        match = re.search(r"Código:\s*(\d{6})", body)
    assert match is not None, body
    return match.group(1)


def _recovery_code_from_outbox() -> str:
    body = mail.outbox[-1].body
    match = re.search(r"Codigo:\s*(\d{6})", body)
    if match is None:
        match = re.search(r"Código:\s*(\d{6})", body)
    assert match is not None, body
    return match.group(1)


def _confirm_reset(client, email, code, new_password="newpass12"):
    return client.post(
        "/api/auth/password-reset/confirm/",
        {
            "email": email,
            "code": code,
            "new_password": new_password,
        },
        format="json",
    )


@override_settings(
    EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
)
class PasswordResetApiTests(APITestCase):
    GENERIC = "If an account exists, a recovery message was sent."

    def test_unknown_email_same_generic_response_no_mail(self):
        response = self.client.post(
            "/api/auth/password-reset/request/",
            {"email": "nobody@example.com"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data.get("detail"), self.GENERIC)
        self.assertEqual(len(mail.outbox), 0)
        self.assertFalse(PasswordResetToken.objects.exists())

    def test_known_email_does_not_echo_token_or_existence(self):
        _make_user(email="reset@example.com", password="oldpass12")
        response = self.client.post(
            "/api/auth/password-reset/request/",
            {"email": "reset@example.com"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data.get("detail"), self.GENERIC)
        self.assertNotIn("token", response.data)
        self.assertEqual(len(mail.outbox), 1)
        code = _recovery_code_from_outbox()
        self.assertRegex(code, r"^\d{6}$")
        self.assertNotIn(code, str(response.data))
        self.assertNotIn("debug_verification_link", response.data)

    def test_confirm_changes_password_and_token_is_one_time(self):
        user = _make_user(email="once@example.com", password="oldpass12")
        self.client.post(
            "/api/auth/password-reset/request/",
            {"email": "once@example.com"},
            format="json",
        )
        token = _recovery_code_from_outbox()
        first = _confirm_reset(self.client, "once@example.com", token)
        self.assertEqual(first.status_code, 200)
        user.refresh_from_db()
        self.assertTrue(user.check_password("newpass12"))
        self.assertFalse(user.check_password("oldpass12"))

        second = _confirm_reset(self.client, "once@example.com", token)
        self.assertEqual(second.status_code, 400)
        self.assertEqual(second.data.get("code"), "recovery_code_invalid")
        user.refresh_from_db()
        self.assertTrue(user.check_password("newpass12"))

        login = self.client.post(
            "/api/auth/login/",
            {"email": "once@example.com", "password": "newpass12"},
            format="json",
        )
        self.assertEqual(login.status_code, 200)
        self.assertTrue(login.data.get("access"))

    def test_expired_token_rejected(self):
        user = _make_user(email="exp@example.com", password="oldpass12")
        self.client.post(
            "/api/auth/password-reset/request/",
            {"email": "exp@example.com"},
            format="json",
        )
        token = _recovery_code_from_outbox()
        PasswordResetToken.objects.filter(user=user).update(
            expires_at=timezone.now() - timedelta(seconds=1)
        )
        response = _confirm_reset(self.client, "exp@example.com", token)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data.get("code"), "recovery_code_expired")
        user.refresh_from_db()
        self.assertTrue(user.check_password("oldpass12"))

    def test_invalid_token_rejected(self):
        response = _confirm_reset(
            self.client, "ghost@example.com", "123456"
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data.get("code"), "recovery_code_invalid")

    def test_short_password_rejected_without_consuming_token(self):
        _make_user(email="shortpw@example.com", password="oldpass12")
        self.client.post(
            "/api/auth/password-reset/request/",
            {"email": "shortpw@example.com"},
            format="json",
        )
        token = _recovery_code_from_outbox()
        response = _confirm_reset(
            self.client, "shortpw@example.com", token, new_password="1234567"
        )
        self.assertEqual(response.status_code, 400)
        row = PasswordResetToken.objects.get(
            user__email="shortpw@example.com", used_at__isnull=True
        )
        self.assertIsNone(row.used_at)

    def test_new_request_invalidates_previous_unused_token(self):
        _make_user(email="rotate@example.com", password="oldpass12")
        self.client.post(
            "/api/auth/password-reset/request/",
            {"email": "rotate@example.com"},
            format="json",
        )
        first = _recovery_code_from_outbox()
        self.client.post(
            "/api/auth/password-reset/request/",
            {"email": "rotate@example.com"},
            format="json",
        )
        second = _recovery_code_from_outbox()
        self.assertNotEqual(first, second)
        stale = _confirm_reset(self.client, "rotate@example.com", first)
        self.assertEqual(stale.status_code, 400)
        ok = _confirm_reset(self.client, "rotate@example.com", second)
        self.assertEqual(ok.status_code, 200)

    def test_recovery_hash_is_distinct_from_verification_hash(self):
        from accounts.services.email_verification_code import hash_verification_code
        from accounts.services.password_reset import hash_reset_token

        user = _make_user(email="sep@example.com", password="oldpass12")
        self.client.post(
            "/api/auth/password-reset/request/",
            {"email": "sep@example.com"},
            format="json",
        )
        code = _recovery_code_from_outbox()
        row = PasswordResetToken.objects.get(user=user, used_at__isnull=True)
        self.assertEqual(row.token_hash, hash_reset_token(user.pk, code))
        self.assertNotEqual(row.token_hash, hash_verification_code(user.pk, code))
        self.assertNotEqual(row.token_hash, code)

    def test_too_many_wrong_codes_are_throttled(self):
        user = _make_user(email="lock@example.com", password="oldpass12")
        self.client.post(
            "/api/auth/password-reset/request/",
            {"email": "lock@example.com"},
            format="json",
        )
        real = _recovery_code_from_outbox()
        wrong = "000000" if real != "000000" else "111111"
        last = None
        for _ in range(5):
            last = _confirm_reset(self.client, "lock@example.com", wrong)
        self.assertEqual(last.status_code, 429, last.data)
        self.assertEqual(last.data.get("code"), "too_many_attempts")
        blocked = _confirm_reset(self.client, "lock@example.com", real)
        self.assertEqual(blocked.status_code, 400)
        user.refresh_from_db()
        self.assertTrue(user.check_password("oldpass12"))


class SessionApiTests(APITestCase):
    def _login(self, email="sess@example.com", password="password1"):
        _make_user(email=email, password=password, verified=True)
        response = self.client.post(
            "/api/auth/login/",
            {"email": email, "password": password},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        return response.data["access"], response.data["refresh"]

    def test_refresh_rotates_and_returns_new_access(self):
        _, refresh = self._login()
        response = self.client.post(
            "/api/auth/token/refresh/",
            {"refresh": refresh},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data.get("access"))
        self.assertTrue(response.data.get("refresh"))
        self.assertNotEqual(response.data["refresh"], refresh)

    def test_logout_requires_authentication(self):
        response = self.client.post(
            "/api/auth/logout/",
            {"refresh": "x"},
            format="json",
        )
        self.assertEqual(response.status_code, 401)

    def test_logout_blacklists_refresh(self):
        access, refresh = self._login()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        response = self.client.post(
            "/api/auth/logout/",
            {"refresh": refresh},
            format="json",
        )
        self.assertEqual(response.status_code, 204)
        self.client.credentials()
        blocked = self.client.post(
            "/api/auth/token/refresh/",
            {"refresh": refresh},
            format="json",
        )
        self.assertIn(blocked.status_code, (400, 401))
        self.assertNotIn("access", blocked.data or {})

    def test_logout_idempotent_when_already_blacklisted(self):
        access, refresh = self._login(email="again@example.com")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        first = self.client.post(
            "/api/auth/logout/",
            {"refresh": refresh},
            format="json",
        )
        self.assertEqual(first.status_code, 204)
        second = self.client.post(
            "/api/auth/logout/",
            {"refresh": refresh},
            format="json",
        )
        self.assertEqual(second.status_code, 204)


class BiometricStatusApiTests(APITestCase):
    def _auth(self, email="bio@example.com"):
        _make_user(email=email, password="password1", verified=True)
        login = self.client.post(
            "/api/auth/login/",
            {"email": email, "password": "password1"},
            format="json",
        )
        self.assertEqual(login.status_code, 200)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        return login.data["access"]

    def test_requires_authentication(self):
        response = self.client.get("/api/users/biometric-status/")
        self.assertEqual(response.status_code, 401)

    def test_default_is_disabled_and_put_only_stores_flag(self):
        self._auth()
        got = self.client.get("/api/users/biometric-status/")
        self.assertEqual(got.status_code, 200)
        self.assertFalse(got.data["biometric_enabled"])

        put = self.client.put(
            "/api/users/biometric-status/",
            {"biometric_enabled": True},
            format="json",
        )
        self.assertEqual(put.status_code, 200)
        self.assertEqual(set(put.data.keys()), {"biometric_enabled"})
        self.assertTrue(put.data["biometric_enabled"])

        boot = self.client.get("/api/auth/bootstrap/")
        self.assertTrue(boot.data["biometric_available"])


class EmailVerificationCodeServiceTests(TestCase):
    def test_issued_code_is_six_digits(self):
        from accounts.services.email_verification_code import (
            issue_email_verification_code,
        )

        user = _make_user(email="otp@example.com", verified=False)
        raw = issue_email_verification_code(user)
        self.assertRegex(raw, r"^\d{6}$")

    def test_issued_code_is_stored_hashed_not_plaintext(self):
        from accounts.models import EmailVerificationCode
        from accounts.services.email_verification_code import (
            hash_verification_code,
            issue_email_verification_code,
        )

        user = _make_user(email="hashotp@example.com", verified=False)
        raw = issue_email_verification_code(user)
        row = EmailVerificationCode.objects.get(user=user, used_at__isnull=True)
        self.assertNotEqual(row.code_hash, raw)
        self.assertEqual(row.code_hash, hash_verification_code(user.pk, raw))
        self.assertNotIn(raw, str(row.code_hash))

    def test_correct_code_verifies_user_and_cannot_be_reused(self):
        from accounts.services.email_verification_code import (
            EmailVerificationError,
            confirm_email_verification_code,
            issue_email_verification_code,
        )

        user = _make_user(email="okotp@example.com", verified=False)
        raw = issue_email_verification_code(user)
        confirm_email_verification_code(email=user.email, code=raw)
        user.refresh_from_db()
        self.assertTrue(user.is_verified)
        with self.assertRaises(EmailVerificationError) as ctx:
            confirm_email_verification_code(email=user.email, code=raw)
        self.assertEqual(ctx.exception.code, "verification_code_invalid")

    def test_wrong_code_does_not_verify(self):
        from accounts.services.email_verification_code import (
            EmailVerificationError,
            confirm_email_verification_code,
            issue_email_verification_code,
        )

        user = _make_user(email="badotp@example.com", verified=False)
        issue_email_verification_code(user)
        with self.assertRaises(EmailVerificationError) as ctx:
            confirm_email_verification_code(email=user.email, code="000000")
        self.assertEqual(ctx.exception.code, "verification_code_invalid")
        user.refresh_from_db()
        self.assertFalse(user.is_verified)

    def test_expired_code_is_rejected_with_expired_code(self):
        from accounts.models import EmailVerificationCode
        from accounts.services.email_verification_code import (
            EmailVerificationError,
            confirm_email_verification_code,
            issue_email_verification_code,
        )

        user = _make_user(email="expotp@example.com", verified=False)
        raw = issue_email_verification_code(user)
        EmailVerificationCode.objects.filter(user=user).update(
            expires_at=timezone.now() - timedelta(seconds=1)
        )
        with self.assertRaises(EmailVerificationError) as ctx:
            confirm_email_verification_code(email=user.email, code=raw)
        self.assertEqual(ctx.exception.code, "verification_code_expired")
        user.refresh_from_db()
        self.assertFalse(user.is_verified)

    def test_reissue_invalidates_previous_code(self):
        from accounts.services.email_verification_code import (
            EmailVerificationError,
            confirm_email_verification_code,
            issue_email_verification_code,
        )

        user = _make_user(email="resendotp@example.com", verified=False)
        first = issue_email_verification_code(user)
        second = issue_email_verification_code(user)
        self.assertRegex(second, r"^\d{6}$")
        with self.assertRaises(EmailVerificationError) as ctx:
            confirm_email_verification_code(email=user.email, code=first)
        self.assertEqual(ctx.exception.code, "verification_code_invalid")
        confirm_email_verification_code(email=user.email, code=second)
        user.refresh_from_db()
        self.assertTrue(user.is_verified)
