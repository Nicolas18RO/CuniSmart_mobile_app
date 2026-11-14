import json
from fractions import Fraction
from pathlib import Path

from django.test import SimpleTestCase
from core.kinship import Animal, evaluate


class MatrixEquivalenceTests(SimpleTestCase):
    def test_dense_path_budget_is_not_reported_as_zero(self):
        herd = {str(i): Animal(str(i), None, None, "FOUNDER") for i in range(2)}
        left, right = "0", "1"
        for level in range(10):
            a, b = str(2 * level + 2), str(2 * level + 3)
            herd[a] = Animal(a, left, right, "RECORDED")
            herd[b] = Animal(b, left, right, "RECORDED")
            left, right = a, b
        result = evaluate(left, right, herd)
        self.assertEqual(result.status, "NO_CALCULABLE")
        self.assertIsNone(result.relationship)
        self.assertEqual(result.reason, "LÍMITE_TÉCNICO_DE_GENEALOGÍA")

    def test_shared_independent_matrix_cases(self):
        fixture = json.loads((Path(__file__).parent / "fixtures/r3_relationship_matrix.json").read_text())
        comparisons = 0
        for graph in fixture["graphs"]:
            herd = {
                str(i): Animal(str(i), None if p is None else str(p),
                               None if q is None else str(q),
                               knowledge="FOUNDER" if p is None else "RECORDED")
                for i, (p, q) in enumerate(graph["parents"])
            }
            for left, right, numerator, denominator in graph["expected"]:
                expected = Fraction(int(numerator), int(denominator))
                result = evaluate(left, right, herd)
                self.assertEqual(result.status, "CALCULABLE")
                self.assertEqual(result.relationship, expected)
                self.assertEqual(result.expected_inbreeding, expected / 2)
                self.assertEqual(result.risk_level, "ALTO" if expected / 2 >= Fraction(1, 8)
                                 else "PREVENTIVO" if expected / 2 >= Fraction(1, 16)
                                 else "SIN_ADVERTENCIA")
                comparisons += 1
        self.assertEqual(comparisons, 1350)
