from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from core.genealogy import assign_or_update, build_pedigree, clear_parent
from core.models import ParentLink, Rabbit
from core.tests import _make_verified_user
from core.views import _herd_for
from core.kinship import evaluate


class GenealogyIntegrityTests(TestCase):
    def setUp(self):
        self.owner = _make_verified_user(email="integrity@example.test")
        self.other = _make_verified_user(email="other@example.test")
        self.client = APIClient()
        self.client.force_authenticate(self.owner)
        self.child = self.rabbit("child")
        self.father = self.rabbit("father")
        self.mother = self.rabbit("mother", sex="female")

    def rabbit(self, name, sex="male", owner=None):
        return Rabbit.objects.create(user=owner or self.owner, name=name,
                                     breed="test", sex=sex, birth_date="2025-01-01")

    def assign(self, parent, role="FATHER", version=None):
        return assign_or_update(child=self.child, parent=parent, role=role, version=version)

    def patch(self, rabbit, **body):
        return self.client.patch(f"/api/rabbits/{rabbit.uuid}/", body, format="json")

    def test_transitions_preserve_history_and_partial_is_unknown(self):
        self.assertEqual(self.child.genealogy_knowledge, "UNKNOWN")
        first = self.assign(self.father)
        self.assign(self.mother, "MOTHER")
        self.child.refresh_from_db()
        self.assertEqual(self.child.genealogy_knowledge, "RECORDED")
        clear_parent(child=self.child, role="FATHER", version=first.version)
        self.child.refresh_from_db()
        self.assertEqual(self.child.genealogy_knowledge, "UNKNOWN")
        self.assign(self.father)
        self.assertEqual(list(self.child.genealogy_transitions.values_list("previous", "current")),
                         [("UNKNOWN", "RECORDED"), ("RECORDED", "UNKNOWN"), ("UNKNOWN", "RECORDED")])
        self.assertEqual(ParentLink.objects.filter(child=self.child, role="FATHER").count(), 2)

    def test_founder_requires_explicit_transition(self):
        self.assertEqual(self.client.put(
            f"/api/rabbits/{self.child.uuid}/parents/FATHER/", [], format="json"
        ).status_code, 400)
        response = self.patch(self.child, genealogy_knowledge="FOUNDER", version=1)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.client.put(f"/api/rabbits/{self.child.uuid}/parents/FATHER/",
                                        {"parent_uuid": str(self.father.uuid)}, format="json").status_code, 400)
        self.assertEqual(self.patch(self.child, genealogy_knowledge="UNKNOWN", version=2).status_code, 200)
        self.assign(self.father)
        self.assertEqual(self.patch(self.child, genealogy_knowledge="FOUNDER").status_code, 400)
        self.assertEqual(self.patch(self.child, genealogy_knowledge="RECORDED").status_code, 400)

    def test_create_founder_is_explicit_and_audited(self):
        response = self.client.post(
            "/api/rabbits/",
            {
                "name": "Externo",
                "breed": "Rex",
                "sex": "male",
                "birth_date": "2025-01-01",
                "status": "active",
                "genealogy_knowledge": "FOUNDER",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        rabbit = Rabbit.objects.get(uuid=response.data["uuid"])
        self.assertEqual(rabbit.genealogy_knowledge, "FOUNDER")
        self.assertEqual(
            list(rabbit.genealogy_transitions.values_list("previous", "current")),
            [("UNKNOWN", "FOUNDER")],
        )

    def test_foreign_parent_never_exposed_even_in_corrupt_data(self):
        foreign = self.rabbit("secret", owner=self.other)
        ParentLink.objects.create(child=self.child, parent=foreign, role="FATHER")
        payload = build_pedigree(self.child)
        self.assertNotIn(str(foreign.uuid), str(payload))
        self.assertNotIn("secret", str(payload))
        self.assertEqual(payload["integrity"], "INVALID")
        herd = _herd_for(self.owner)
        self.assertNotIn(str(foreign.uuid), herd)
        self.assertEqual(evaluate(str(self.child.uuid), str(self.father.uuid), herd).status, "NO_CALCULABLE")
        response = self.client.delete(f"/api/rabbits/{self.child.uuid}/parents/FATHER/",
                                      {"version": 1}, format="json")
        self.assertEqual(response.status_code, 404)
        self.assertNotIn(str(foreign.uuid), str(response.data))
        response = self.client.put(f"/api/rabbits/{self.child.uuid}/parents/FATHER/",
                                   {"parent_uuid": str(self.father.uuid), "version": 1}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertNotIn(str(foreign.uuid), str(response.data))

    def test_active_father_and_mother_cannot_change_sex(self):
        self.assign(self.father)
        self.assign(self.mother, "MOTHER")
        for rabbit, sex in [(self.father, "female"), (self.mother, "male")]:
            self.assertEqual(self.patch(rabbit, sex=sex).status_code, 400)
        clear_parent(child=self.child, role="FATHER", version=1)
        self.assertEqual(self.patch(self.father, sex="female").status_code, 200)
        self.assertEqual(self.patch(self.child, sex="female").status_code, 200)

    def test_deleted_ancestor_is_historical_not_selectable_or_calculable(self):
        self.assign(self.father)
        self.father.deleted_at = timezone.now()
        self.father.save(update_fields=["deleted_at"])
        payload = build_pedigree(self.child)
        self.assertTrue(payload["father"]["deleted"])
        self.assertEqual(ParentLink.objects.count(), 1)
        self.assertEqual(evaluate(str(self.child.uuid), str(self.mother.uuid), _herd_for(self.owner)).status, "NO_CALCULABLE")

    def test_cycle_is_reported_without_root_duplicates(self):
        self.assign(self.father)
        ParentLink.objects.create(child=self.father, parent=self.child, role="FATHER")
        payload = build_pedigree(self.child)
        self.assertIn("GENEALOGY_CYCLE", payload["integrityIssues"])
        for key in ("ancestors", "descendants"):
            ids = [item["uuid"] for item in payload[key]]
            self.assertNotIn(str(self.child.uuid), ids)
            self.assertEqual(len(ids), len(set(ids)))

    def test_tree_is_independent_of_persisted_edge_insertion_order(self):
        self.assign(self.father)
        self.assign(self.mother, "MOTHER")
        grandparent = self.rabbit("grandparent")
        ParentLink.objects.create(child=self.father, parent=grandparent, role="FATHER")
        ParentLink.objects.create(child=self.mother, parent=grandparent, role="FATHER")
        before = build_pedigree(self.child)
        rows = list(ParentLink.objects.values("child_id", "parent_id", "role", "version"))
        # Only disposable test rows are rebuilt, in the opposite insertion order.
        ParentLink.objects.all().delete()
        ParentLink.objects.bulk_create([ParentLink(**row) for row in reversed(rows)])
        self.assertEqual(build_pedigree(self.child), before)

    def test_mathematical_query_and_breeding_are_distinct(self):
        url = "/api/rabbits/kinship/"
        self.assertEqual(self.client.get(url, {"a": str(self.father.uuid), "b": str(self.father.uuid)}).status_code, 200)
        for a, b in [(self.father, self.father), (self.child, self.father)]:
            self.assertEqual(self.client.get(url, {"a": str(a.uuid), "b": str(b.uuid), "mode": "breeding"}).status_code, 400)
        response = self.client.get(url, {"a": str(self.father.uuid), "b": str(self.mother.uuid), "mode": "breeding"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status"], "NO_CALCULABLE")
        self.assertIsNone(response.data["expectedInbreeding"])
        self.father.status = "sold"
        self.father.save(update_fields=["status"])
        self.assertEqual(self.client.get(url, {"a": str(self.father.uuid), "b": str(self.mother.uuid), "mode": "breeding"}).status_code, 400)
