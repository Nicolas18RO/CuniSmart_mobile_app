"""R3 E4 — parentesco y consanguinidad. Valores derivados de la fórmula aprobada."""

from fractions import Fraction

from django.test import SimpleTestCase

from core.kinship import (
    HIGH_THRESHOLD,
    PREVENTIVE_THRESHOLD,
    Animal,
    evaluate,
    risk_level_for,
)

F = Fraction


def _herd(*rows):
    # These mathematical fixtures explicitly declare independent founders.
    # This is fixture knowledge, never an inference made by production code.
    return {
        uuid: Animal(
            uuid, father, mother,
            knowledge="FOUNDER" if father is None and mother is None else "RECORDED",
        )
        for uuid, father, mother in rows
    }


class KinshipFormulaTests(SimpleTestCase):
    def test_same_animal(self):
        herd = _herd(("a", None, None))
        result = evaluate("a", "a", herd)
        self.assertEqual(result.status, "CALCULABLE")
        self.assertEqual(result.relationship, F(1))
        self.assertEqual(result.expected_inbreeding, F(1, 2))
        self.assertEqual(result.risk_level, "ALTO")
        self.assertIsNone(result.reason)

    def test_full_siblings(self):
        herd = _herd(
            ("gf", None, None),
            ("gm", None, None),
            ("s1", "gf", "gm"),
            ("s2", "gf", "gm"),
        )
        result = evaluate("s1", "s2", herd)
        self.assertEqual(result.relationship, F(1, 2))
        self.assertEqual(result.expected_inbreeding, F(1, 4))
        self.assertEqual(len(result.common_ancestors), 2)
        self.assertEqual(result.risk_level, "ALTO")

    def test_half_siblings(self):
        herd = _herd(
            ("father", None, None),
            ("m1", None, None),
            ("m2", None, None),
            ("a", "father", "m1"),
            ("b", "father", "m2"),
        )
        result = evaluate("a", "b", herd)
        self.assertEqual(result.relationship, F(1, 4))
        self.assertEqual(result.expected_inbreeding, F(1, 8))
        self.assertEqual(result.risk_level, "ALTO")

    def test_father_daughter(self):
        herd = {
            "sire": Animal("sire", None, None, "FOUNDER", "", "male"),
            "dam": Animal("dam", None, None, "FOUNDER", "", "female"),
            "daughter": Animal(
                "daughter", "sire", "dam", "RECORDED", "", "female"
            ),
        }
        result = evaluate("sire", "daughter", herd)
        self.assertEqual(result.relationship, F(1, 2))
        self.assertEqual(result.expected_inbreeding, F(1, 4))
        self.assertEqual(result.relationship_type, "FATHER_DAUGHTER")
        self.assertTrue(result.is_exact)
        self.assertEqual(result.minimum_known_inbreeding, F(1, 4))

    def test_unknown_father_daughter_exposes_a_high_minimum(self):
        herd = {
            "sire": Animal("sire", None, None, "UNKNOWN", "Pepe", "male"),
            "dam": Animal("dam", None, None, "UNKNOWN", "Lupe", "female"),
            "daughter": Animal(
                "daughter", "sire", "dam", "RECORDED", "Mónica", "female"
            ),
        }
        result = evaluate("sire", "daughter", herd)
        self.assertEqual(result.status, "PARTIAL")
        self.assertEqual(result.relationship_type, "FATHER_DAUGHTER")
        self.assertEqual(result.relationship, F(1, 2))
        self.assertIsNone(result.expected_inbreeding)
        self.assertEqual(result.minimum_known_inbreeding, F(1, 4))
        self.assertFalse(result.is_exact)
        self.assertEqual(result.risk_level, "ALTO")
        self.assertEqual([item.uuid for item in result.common_ancestors], ["sire"])
        self.assertEqual(result.common_ancestors[0].name, "Pepe")
        self.assertIn("sire", result.unknown_branches)
        self.assertIn("INCOMPLETE_GENEALOGY", result.warnings)
        payload = result.to_payload()
        self.assertEqual(payload["relationshipCoefficient"], "0.5")
        self.assertIsNone(payload["expectedInbreeding"])
        self.assertEqual(payload["minimumKnownInbreeding"], "0.25")
        self.assertFalse(payload["isExact"])

    def test_grandfather_granddaughter(self):
        herd = _herd(
            ("gf", None, None),
            ("gm", None, None),
            ("father", "gf", "gm"),
            ("dam", None, None),
            ("granddaughter", "father", "dam"),
        )
        result = evaluate("gf", "granddaughter", herd)
        self.assertEqual(result.relationship, F(1, 4))
        self.assertEqual(result.expected_inbreeding, F(1, 8))

    def test_first_cousins(self):
        herd = _herd(
            ("gf", None, None),
            ("gm", None, None),
            ("s1", "gf", "gm"),
            ("s2", "gf", "gm"),
            ("d1", None, None),
            ("d2", None, None),
            ("c1", "s1", "d1"),
            ("c2", "s2", "d2"),
        )
        result = evaluate("c1", "c2", herd)
        self.assertEqual(result.relationship, F(1, 8))
        self.assertEqual(result.expected_inbreeding, F(1, 16))
        self.assertEqual(result.risk_level, "PREVENTIVO")

    def test_no_common_ancestor_when_pedigree_is_complete(self):
        herd = _herd(
            ("f1", None, None),
            ("m1", None, None),
            ("f2", None, None),
            ("m2", None, None),
            ("a", "f1", "m1"),
            ("b", "f2", "m2"),
        )
        result = evaluate("a", "b", herd)
        self.assertEqual(result.status, "CALCULABLE")
        self.assertEqual(result.relationship, F(0))
        self.assertEqual(result.expected_inbreeding, F(0))
        self.assertEqual(result.common_ancestors, [])
        self.assertEqual(result.risk_level, "SIN_ADVERTENCIA")
        self.assertIsNone(result.reason)
        self.assertTrue(result.independence_assumption_applied)
        self.assertEqual(len(result.declared_founders), 4)
        payload = result.to_payload()
        self.assertTrue(payload["independenceAssumptionApplied"])

    def test_uncle_and_first_cousins_have_specific_relationship_types(self):
        herd = _herd(
            ("gf", None, None),
            ("gm", None, None),
            ("uncle", "gf", "gm"),
            ("parent", "gf", "gm"),
            ("outside1", None, None),
            ("outside2", None, None),
            ("niece", "parent", "outside1"),
            ("cousin", "uncle", "outside2"),
        )
        self.assertEqual(
            evaluate("uncle", "niece", herd).relationship_type,
            "UNCLE_AUNT_NEPHEW_NIECE",
        )
        self.assertEqual(
            evaluate("niece", "cousin", herd).relationship_type,
            "FIRST_COUSINS",
        )

    def test_incomplete_genealogy_is_not_zero(self):
        herd = _herd(
            ("dam", None, None),
            ("a", None, "dam"),
            ("b", None, None),
        )
        result = evaluate("a", "b", herd)
        self.assertEqual(result.status, "NO_CALCULABLE")
        self.assertIsNone(result.relationship)
        self.assertIsNone(result.expected_inbreeding)
        self.assertNotEqual(result.relationship, F(0))
        self.assertEqual(result.risk_level, "NO_CALCULABLE")
        self.assertEqual(result.reason, "INFORMACIÓN_GENEALÓGICA_INSUFICIENTE")
        self.assertFalse(result.is_exact)
        self.assertIsNone(result.minimum_known_inbreeding)

    def test_inbred_ancestor_increases_the_coefficient(self):
        herd = _herd(
            ("gf", None, None),
            ("gm", None, None),
            ("p", "gf", "gm"),
            ("q", "gf", "gm"),
            ("inbred", "p", "q"),
            ("outsider", None, None),
            ("daughter", "inbred", "outsider"),
        )
        result = evaluate("inbred", "daughter", herd)
        self.assertEqual(result.relationship, F(5, 8))
        self.assertEqual(result.expected_inbreeding, F(5, 16))

    def test_multiple_common_ancestors_are_both_counted(self):
        herd = _herd(
            ("gf", None, None),
            ("gm", None, None),
            ("s1", "gf", "gm"),
            ("s2", "gf", "gm"),
        )
        result = evaluate("s1", "s2", herd)
        identities = {item.uuid for item in result.common_ancestors}
        self.assertEqual(identities, {"gf", "gm"})
        self.assertEqual(sum(item.contribution for item in result.common_ancestors), F(1, 2))

    def test_deeper_ancestors_are_not_double_counted(self):
        herd = _herd(
            ("gf", None, None),
            ("gm", None, None),
            ("sire", "gf", "gm"),
            ("dam", None, None),
            ("daughter", "sire", "dam"),
        )
        result = evaluate("sire", "daughter", herd)
        self.assertEqual(result.relationship, F(1, 2))
        self.assertEqual([item.uuid for item in result.common_ancestors], ["sire"])

    def test_result_is_deterministic(self):
        herd = _herd(
            ("gf", None, None),
            ("gm", None, None),
            ("s1", "gf", "gm"),
            ("s2", "gf", "gm"),
        )
        first = evaluate("s1", "s2", herd)
        second = evaluate("s2", "s1", herd)
        self.assertEqual(first.relationship, second.relationship)
        self.assertEqual(first.expected_inbreeding, second.expected_inbreeding)
        self.assertEqual(
            sorted(item.uuid for item in first.common_ancestors),
            sorted(item.uuid for item in second.common_ancestors),
        )

    def test_threshold_just_below_preventive(self):
        self.assertEqual(risk_level_for(PREVENTIVE_THRESHOLD - F(1, 10000)), "SIN_ADVERTENCIA")

    def test_threshold_exactly_preventive(self):
        self.assertEqual(PREVENTIVE_THRESHOLD, F(1, 16))
        self.assertEqual(risk_level_for(PREVENTIVE_THRESHOLD), "PREVENTIVO")

    def test_threshold_just_above_preventive(self):
        self.assertEqual(risk_level_for(PREVENTIVE_THRESHOLD + F(1, 10000)), "PREVENTIVO")

    def test_threshold_just_below_high(self):
        self.assertEqual(risk_level_for(HIGH_THRESHOLD - F(1, 10000)), "PREVENTIVO")

    def test_threshold_exactly_high(self):
        self.assertEqual(HIGH_THRESHOLD, F(1, 8))
        self.assertEqual(risk_level_for(HIGH_THRESHOLD), "ALTO")

    def test_threshold_just_above_high(self):
        self.assertEqual(risk_level_for(HIGH_THRESHOLD + F(1, 10000)), "ALTO")

    def test_no_calculable_payload_does_not_emit_zero(self):
        herd = _herd(("a", "missing-father", None), ("b", None, None))
        payload = evaluate("a", "b", herd).to_payload()
        self.assertEqual(payload["status"], "NO_CALCULABLE")
        self.assertIsNone(payload["relationshipCoefficient"])
        self.assertIsNone(payload["expectedInbreeding"])
        self.assertNotEqual(payload["relationshipCoefficient"], "0")
        self.assertNotEqual(payload["expectedInbreeding"], "0")
        self.assertIsNone(payload["minimumKnownInbreeding"])
        self.assertFalse(payload["isExact"])
