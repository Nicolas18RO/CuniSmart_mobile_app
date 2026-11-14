"""R3 knowledge contract: no database access is required by these tests."""

from django.test import SimpleTestCase

from core.kinship import Animal, evaluate


class GenealogyKnowledgeTests(SimpleTestCase):
    def test_version_is_a_strict_positive_integer(self):
        from core.views import _optional_version
        from rest_framework.exceptions import ValidationError

        for value in (True, False, 1.9, -1, 0, "1", "bad", 2147483648):
            with self.subTest(value=value):
                with self.assertRaises(ValidationError):
                    _optional_version({"version": value})
        self.assertEqual(_optional_version({"version": 1}), 1)

    def test_missing_parents_do_not_declare_founders(self):
        herd = {key: Animal(key, None, None) for key in ("a", "b")}
        result = evaluate("a", "b", herd)
        self.assertEqual(result.status, "NO_CALCULABLE")
        self.assertIsNone(result.relationship)
        self.assertIsNone(result.expected_inbreeding)
        self.assertEqual(result.risk_level, "NO_CALCULABLE")

    def test_explicit_independent_founders_are_calculable(self):
        herd = {
            key: Animal(key, None, None, knowledge="FOUNDER")
            for key in ("a", "b")
        }
        result = evaluate("a", "b", herd)
        self.assertEqual(result.status, "CALCULABLE")
        self.assertEqual(result.relationship, 0)

    def test_unknown_branch_is_not_zero(self):
        herd = {
            "a": Animal("a", "p", "q", knowledge="RECORDED"),
            "p": Animal("p", None, None, knowledge="FOUNDER"),
            "q": Animal("q", None, None),
            "b": Animal("b", None, None, knowledge="FOUNDER"),
        }
        self.assertEqual(evaluate("a", "b", herd).status, "NO_CALCULABLE")

    def test_founder_with_parents_is_inconsistent(self):
        herd = {
            "a": Animal("a", "p", "q", knowledge="FOUNDER"),
            "p": Animal("p", None, None, knowledge="FOUNDER"),
            "q": Animal("q", None, None, knowledge="FOUNDER"),
        }
        self.assertEqual(evaluate("a", "p", herd).status, "NO_CALCULABLE")

    def test_recorded_requires_both_parents(self):
        herd = {
            "a": Animal("a", "p", None, knowledge="RECORDED"),
            "p": Animal("p", None, None, knowledge="FOUNDER"),
        }
        self.assertEqual(evaluate("a", "p", herd).status, "NO_CALCULABLE")
