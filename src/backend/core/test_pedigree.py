"""R3 E3 — árbol calculado: generaciones, ramas, deduplicación y ciclos."""

from core.models import ParentLink, Rabbit
from core.tests import _RabbitApiTestCase, _make_verified_user

RABBITS_URL = "/api/rabbits/"


def _pedigree_url(rabbit_uuid):
    return f"{RABBITS_URL}{rabbit_uuid}/pedigree/"


class PedigreeTreeTests(_RabbitApiTestCase):
    def test_shortest_ancestry_propagates_to_earlier_ancestors(self):
        root = self._rabbit(self.user_a.email, name="Root", sex="male")
        father = self._rabbit(self.user_a.email, name="Father", sex="male")
        mother = self._rabbit(self.user_a.email, name="Mother", sex="female")
        middle = self._rabbit(self.user_a.email, name="Middle", sex="male")
        common = self._rabbit(self.user_a.email, name="Common", sex="male")
        oldest = self._rabbit(self.user_a.email, name="Oldest", sex="male")
        for child, parent, role in [
            (root, father, "FATHER"), (root, mother, "MOTHER"),
            (father, middle, "FATHER"), (middle, common, "FATHER"),
            (mother, common, "FATHER"), (common, oldest, "FATHER"),
        ]:
            self._link(child, parent, role)
        response, generations = self._generations(root)
        self.assertEqual(generations[str(common.uuid)], 2)
        self.assertEqual(generations[str(oldest.uuid)], 3)
        self.assertEqual(response.data["integrity"], "VALID")

    def setUp(self):
        self.user_a = _make_verified_user(email="tree-a@example.com")
        self.user_b = _make_verified_user(email="tree-b@example.com")
        self._auth(self.user_a.email)

    def _rabbit(self, email, **overrides):
        created = self._create_as(email, **overrides)
        return Rabbit.objects.get(uuid=created.data["uuid"])

    def _link(self, child, parent, role):
        self._auth(self.user_a.email)
        response = self.client.put(
            f"{RABBITS_URL}{child.uuid}/parents/{role}/",
            {"parent_uuid": str(parent.uuid)},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        return response

    def _generations(self, rabbit):
        self._auth(self.user_a.email)
        response = self.client.get(_pedigree_url(rabbit.uuid))
        self.assertEqual(response.status_code, 200, response.data)
        found = {
            item["uuid"]: item["generation"] for item in response.data["ancestors"]
        }
        found.update(
            {
                item["uuid"]: item["generation"]
                for item in response.data["descendants"]
            }
        )
        return response, found

    def test_one_generation_is_only_the_animal(self):
        animal = self._rabbit(self.user_a.email, name="Solo", sex="female")
        self._auth(self.user_a.email)
        response = self.client.get(_pedigree_url(animal.uuid))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["animal"]["generation"], 0)
        self.assertIsNone(response.data["father"])
        self.assertIsNone(response.data["mother"])
        self.assertEqual(response.data["ancestors"], [])
        self.assertEqual(response.data["descendants"], [])

    def test_two_generations_stop_at_the_parents(self):
        child = self._rabbit(self.user_a.email, name="Cría", sex="female")
        sire = self._rabbit(self.user_a.email, name="Padre", sex="male")
        dam = self._rabbit(self.user_a.email, name="Madre", sex="female")
        self._link(child, sire, "FATHER")
        self._link(child, dam, "MOTHER")
        response, generations = self._generations(child)
        self.assertEqual(set(generations), {str(sire.uuid), str(dam.uuid)})
        self.assertEqual(generations[str(sire.uuid)], 1)
        self.assertEqual(generations[str(dam.uuid)], 1)
        self.assertEqual(response.data["father"]["uuid"], str(sire.uuid))
        self.assertEqual(response.data["mother"]["uuid"], str(dam.uuid))

    def test_ascent_reaches_the_grandparent(self):
        child = self._rabbit(self.user_a.email, name="Cría", sex="male")
        sire = self._rabbit(self.user_a.email, name="Padre", sex="male")
        grandfather = self._rabbit(self.user_a.email, name="Abuelo", sex="male")
        self._link(sire, grandfather, "FATHER")
        self._link(child, sire, "FATHER")
        _, generations = self._generations(child)
        self.assertEqual(generations[str(sire.uuid)], 1)
        self.assertEqual(generations[str(grandfather.uuid)], 2)

    def test_descent_reaches_the_grandchild(self):
        grandparent = self._rabbit(self.user_a.email, name="Abuelo", sex="male")
        parent = self._rabbit(self.user_a.email, name="Padre", sex="male")
        grandchild = self._rabbit(self.user_a.email, name="Nieto", sex="female")
        self._link(parent, grandparent, "FATHER")
        self._link(grandchild, parent, "FATHER")
        _, generations = self._generations(grandparent)
        self.assertEqual(generations[str(parent.uuid)], -1)
        self.assertEqual(generations[str(grandchild.uuid)], -2)
        response, _ = self._generations(grandparent)
        by_uuid = {row["uuid"]: row for row in response.data["descendants"]}
        self.assertEqual(by_uuid[str(parent.uuid)]["relationship"], "SON")
        self.assertEqual(by_uuid[str(grandchild.uuid)]["relationship"], "GRANDDAUGHTER")
        self.assertEqual(by_uuid[str(parent.uuid)]["genealogyKnowledge"], "UNKNOWN")

    def test_father_without_parents_has_an_empty_ascent(self):
        child = self._rabbit(self.user_a.email, name="Cría", sex="female")
        sire = self._rabbit(self.user_a.email, name="Padre", sex="male")
        self._link(child, sire, "FATHER")
        response, _generations = self._generations(sire)
        self.assertIsNone(response.data["father"])
        self.assertIsNone(response.data["mother"])
        self.assertEqual(response.data["ancestors"], [])
        self.assertEqual(response.data["descendants"][0]["uuid"], str(child.uuid))

    def test_child_of_unknown_parent_child_pair_exposes_individual_minimum(self):
        pepe = self._rabbit(self.user_a.email, name="Pepe", sex="male")
        lupe = self._rabbit(self.user_a.email, name="Lupe", sex="female")
        monica = self._rabbit(self.user_a.email, name="Mónica", sex="female")
        juan = self._rabbit(self.user_a.email, name="Juan 2", sex="male")
        self._link(monica, pepe, "FATHER")
        self._link(monica, lupe, "MOTHER")
        self._link(juan, pepe, "FATHER")
        self._link(juan, monica, "MOTHER")
        self._auth(self.user_a.email)
        response = self.client.get(_pedigree_url(juan.uuid))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["father"]["name"], "Pepe")
        self.assertEqual(response.data["mother"]["name"], "Mónica")
        self.assertEqual(response.data["father"]["relationship"], "FATHER")
        self.assertEqual(response.data["mother"]["relationship"], "MOTHER")
        individual = response.data["individualInbreeding"]
        self.assertEqual(individual["status"], "PARTIAL")
        self.assertIsNone(individual["coefficient"])
        self.assertEqual(individual["minimumKnownCoefficient"], "0.25")
        self.assertFalse(individual["isExact"])
        self.assertEqual(individual["riskLevel"], "ALTO")

    def test_incomplete_branch_does_not_invent_a_mother(self):
        child = self._rabbit(self.user_a.email, name="Cría", sex="female")
        sire = self._rabbit(self.user_a.email, name="Padre", sex="male")
        grandfather = self._rabbit(self.user_a.email, name="Abuelo", sex="male")
        self._link(sire, grandfather, "FATHER")
        self._link(child, sire, "FATHER")
        response, generations = self._generations(child)
        self.assertIsNone(response.data["mother"])
        self.assertNotIn(None, generations)
        self.assertEqual(
            set(generations),
            {str(sire.uuid), str(grandfather.uuid)},
        )

    def test_multiple_descendants_are_listed(self):
        sire = self._rabbit(self.user_a.email, name="Padre", sex="male")
        first = self._rabbit(self.user_a.email, name="Uno", sex="female")
        second = self._rabbit(self.user_a.email, name="Dos", sex="male")
        third = self._rabbit(self.user_a.email, name="Tres", sex="female")
        self._link(first, sire, "FATHER")
        self._link(second, sire, "FATHER")
        self._link(third, sire, "FATHER")
        response, generations = self._generations(sire)
        self.assertEqual(
            set(generations),
            {str(first.uuid), str(second.uuid), str(third.uuid)},
        )
        self.assertEqual(len(response.data["descendants"]), 3)

    def test_shared_ancestor_is_listed_once(self):
        child = self._rabbit(self.user_a.email, name="Cría", sex="female")
        sire = self._rabbit(self.user_a.email, name="Padre", sex="male")
        dam = self._rabbit(self.user_a.email, name="Madre", sex="female")
        shared = self._rabbit(self.user_a.email, name="Común", sex="male")
        self._link(sire, shared, "FATHER")
        self._link(dam, shared, "FATHER")
        self._link(child, sire, "FATHER")
        self._link(child, dam, "MOTHER")
        response, generations = self._generations(child)
        self.assertEqual(generations[str(shared.uuid)], 2)
        listed = [
            item["uuid"]
            for item in response.data["ancestors"]
            if item["uuid"] == str(shared.uuid)
        ]
        self.assertEqual(listed, [str(shared.uuid)])

    def test_unexpected_cycle_does_not_loop(self):
        first = self._rabbit(self.user_a.email, name="Uno", sex="male")
        second = self._rabbit(self.user_a.email, name="Dos", sex="male")
        ParentLink.objects.create(child=second, parent=first, role=ParentLink.Role.FATHER)
        ParentLink.objects.create(child=first, parent=second, role=ParentLink.Role.FATHER)
        self._auth(self.user_a.email)
        response = self.client.get(_pedigree_url(first.uuid))
        self.assertEqual(response.status_code, 200, response.data)
        ancestor_ids = [item["uuid"] for item in response.data["ancestors"]]
        self.assertEqual(len(ancestor_ids), len(set(ancestor_ids)))
        self.assertLessEqual(len(ancestor_ids), 2)

    def test_other_owners_rabbit_is_not_a_descendant(self):
        sire = self._rabbit(self.user_a.email, name="Padre", sex="male")
        foreign = self._rabbit(self.user_b.email, name="Ajeno", sex="female")
        ParentLink.objects.create(
            child=foreign,
            parent=sire,
            role=ParentLink.Role.FATHER,
        )
        self._auth(self.user_a.email)
        response = self.client.get(_pedigree_url(sire.uuid))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["descendants"], [])
        self._auth(self.user_b.email)
        hidden = self.client.get(_pedigree_url(sire.uuid))
        self.assertEqual(hidden.status_code, 404)
