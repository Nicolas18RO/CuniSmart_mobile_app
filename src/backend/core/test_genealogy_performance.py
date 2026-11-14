from time import perf_counter
from django.test import TestCase
from django.db import connection
from django.test.utils import CaptureQueriesContext

from core.models import Rabbit, ParentLink
from core.genealogy import build_pedigree
from core.views import _herd_for
from core.kinship import evaluate
from core.tests import _make_verified_user


class GraphQueryBudgetTests(TestCase):
    def test_increasing_complete_pedigrees_have_constant_query_counts(self):
        owner = _make_verified_user(email="scale@example.test")
        def rabbit(name, sex="male", knowledge="FOUNDER"):
            return Rabbit.objects.create(user=owner, name=name, breed="test", sex=sex,
                                         birth_date="2020-01-01", genealogy_knowledge=knowledge)
        previous = rabbit("founder")
        for level in range(1, 33):
            mother = rabbit(f"mother{level}", "female")
            child = rabbit(f"child{level}", knowledge="RECORDED")
            ParentLink.objects.bulk_create([
                ParentLink(child=child, parent=previous, role="FATHER"),
                ParentLink(child=child, parent=mother, role="MOTHER"),
            ])
            if level in (4, 12, 32):
                with CaptureQueriesContext(connection) as tree_queries:
                    start = perf_counter()
                    payload = build_pedigree(child)
                    tree_ms = (perf_counter() - start) * 1000
                with CaptureQueriesContext(connection) as herd_queries:
                    herd = _herd_for(owner)
                start = perf_counter()
                result = evaluate(str(child.uuid), str(previous.uuid), herd)
                calculation_ms = (perf_counter() - start) * 1000
                self.assertEqual(len(tree_queries), 1)
                self.assertEqual(len(herd_queries), 2)
                self.assertEqual(result.status, "CALCULABLE")
                self.assertEqual(len(payload["ancestors"]), 2 * level)
                print(f"R3_SCALE animals={2 * level + 1} edges={2 * level} "
                      f"tree_queries={len(tree_queries)} herd_queries={len(herd_queries)} "
                      f"tree_ms={tree_ms:.3f} calculation_ms={calculation_ms:.3f}")
            previous = child
