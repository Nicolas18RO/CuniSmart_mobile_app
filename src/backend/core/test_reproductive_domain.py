from datetime import date

from django.test import SimpleTestCase

from core.reproductive_domain import (
    RabbitFacts, ReproductiveRuleError, calendar_state, estimated_birth_date,
    validate_calendar_range, validate_pair,
)


class ReproductiveDomainTests(SimpleTestCase):
    def facts(self, uuid, sex, **overrides):
        values = dict(owner_id=1, status="active", deleted=False)
        values.update(overrides)
        return RabbitFacts(uuid, sex=sex, **values)

    def test_estimated_birth_is_exactly_31_calendar_days(self):
        cases = [
            (date(2026, 1, 1), date(2026, 2, 1)),
            (date(2026, 12, 15), date(2027, 1, 15)),
            (date(2024, 1, 30), date(2024, 3, 1)),
        ]
        for mating, expected in cases:
            with self.subTest(mating=mating):
                self.assertEqual(estimated_birth_date(mating), expected)

    def test_pair_invariants(self):
        male = self.facts("m", "male")
        female = self.facts("f", "female")
        validate_pair(male, female, 1)
        invalid = [
            (female, female),
            (self.facts("m", "female"), female),
            (male, self.facts("f", "male")),
            (male, self.facts("f", "female", owner_id=2)),
            (self.facts("m", "male", deleted=True), female),
            (male, self.facts("f", "female", status="sold")),
        ]
        for left, right in invalid:
            with self.assertRaises(ReproductiveRuleError):
                validate_pair(left, right, 1)

    def test_calendar_states_and_ranges(self):
        today = date(2026, 11, 9)
        self.assertEqual(calendar_state(date(2026, 11, 8), today), "OVERDUE")
        self.assertEqual(calendar_state(today, today), "DUE_TODAY")
        self.assertEqual(calendar_state(date(2026, 11, 10), today), "UPCOMING")
        validate_calendar_range(today, date(2027, 11, 10))
        for start, end in [(today, date(2027, 11, 11)), (date(2026, 11, 10), today)]:
            with self.assertRaises(ReproductiveRuleError):
                validate_calendar_range(start, end)
