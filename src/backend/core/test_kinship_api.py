"""R3 E4 — el endpoint expone el mismo motor y respeta ownership."""

from core.tests import _RabbitApiTestCase, _make_verified_user

KINSHIP_URL = "/api/rabbits/kinship/"


class KinshipApiTests(_RabbitApiTestCase):
    def setUp(self):
        self.user_a = _make_verified_user(email="kin-a@example.com")
        self.user_b = _make_verified_user(email="kin-b@example.com")

    def _rabbit(self, email, **overrides):
        created = self._create_as(email, **overrides)
        return created.data["uuid"]

    def _parent(self, child, parent, role):
        self._auth("kin-a@example.com")
        response = self.client.put(
            f"/api/rabbits/{child}/parents/{role}/",
            {"parent_uuid": parent},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)

    def test_anonymous_cannot_query_kinship(self):
        response = self.client.get(KINSHIP_URL, {"a": "a", "b": "b"})
        self.assertEqual(response.status_code, 401)

    def test_other_owner_is_hidden(self):
        own = self._rabbit("kin-a@example.com", name="Propio", sex="male")
        foreign = self._rabbit("kin-b@example.com", name="Ajeno", sex="female")
        self._auth("kin-a@example.com")
        response = self.client.get(KINSHIP_URL, {"a": own, "b": foreign})
        self.assertEqual(response.status_code, 404)

    def test_full_siblings_match_the_formula(self):
        father = self._rabbit("kin-a@example.com", name="Padre", sex="male", genealogy_knowledge="FOUNDER")
        mother = self._rabbit("kin-a@example.com", name="Madre", sex="female", genealogy_knowledge="FOUNDER")
        first = self._rabbit("kin-a@example.com", name="Uno", sex="male")
        second = self._rabbit("kin-a@example.com", name="Dos", sex="female")
        self._parent(first, father, "FATHER")
        self._parent(first, mother, "MOTHER")
        self._parent(second, father, "FATHER")
        self._parent(second, mother, "MOTHER")
        self._auth("kin-a@example.com")
        response = self.client.get(KINSHIP_URL, {"a": first, "b": second})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "CALCULABLE")
        self.assertEqual(response.data["relationshipCoefficient"], "0.5")
        self.assertEqual(response.data["expectedInbreeding"], "0.25")
        self.assertEqual(response.data["riskLevel"], "ALTO")
        self.assertIsNone(response.data["reason"])
        self.assertEqual(len(response.data["commonAncestors"]), 2)
        self.assertEqual(response.data["relationshipType"], "FULL_SIBLINGS")
        self.assertTrue(response.data["isExact"])

    def test_two_declared_founders_are_zero_only_under_declared_assumption(self):
        pepe = self._rabbit(
            "kin-a@example.com", name="Pepe", sex="male",
            genealogy_knowledge="FOUNDER",
        )
        lupe = self._rabbit(
            "kin-a@example.com", name="Lupe", sex="female",
            genealogy_knowledge="FOUNDER",
        )
        self._auth("kin-a@example.com")
        response = self.client.get(KINSHIP_URL, {"a": pepe, "b": lupe})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "CALCULABLE")
        self.assertEqual(response.data["relationshipCoefficient"], "0")
        self.assertEqual(response.data["expectedInbreeding"], "0")
        self.assertTrue(response.data["independenceAssumptionApplied"])
        self.assertEqual(response.data["declaredFounders"], ["Lupe", "Pepe"])

    def test_unknown_parent_child_returns_known_minimum_instead_of_hiding_it(self):
        father = self._rabbit(
            "kin-a@example.com", name="Pepe", sex="male",
            genealogy_knowledge="UNKNOWN",
        )
        mother = self._rabbit(
            "kin-a@example.com", name="Lupe", sex="female",
            genealogy_knowledge="UNKNOWN",
        )
        daughter = self._rabbit(
            "kin-a@example.com", name="Mónica", sex="female",
        )
        self._parent(daughter, father, "FATHER")
        self._parent(daughter, mother, "MOTHER")
        self._auth("kin-a@example.com")
        response = self.client.get(
            KINSHIP_URL,
            {"a": father, "b": daughter, "mode": "breeding"},
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "PARTIAL")
        self.assertEqual(response.data["relationshipType"], "FATHER_DAUGHTER")
        self.assertEqual(response.data["relationshipCoefficient"], "0.5")
        self.assertIsNone(response.data["expectedInbreeding"])
        self.assertEqual(response.data["minimumKnownInbreeding"], "0.25")
        self.assertFalse(response.data["isExact"])
        self.assertEqual(response.data["riskLevel"], "ALTO")
        self.assertEqual(response.data["commonAncestors"][0]["name"], "Pepe")
