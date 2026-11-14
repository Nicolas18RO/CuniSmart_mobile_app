"""Serialize graph writes per owner, including shared Rabbit mutations.

The owner row exists before any edge and therefore also locks empty graph slots.
All cooperating writers acquire it first; locking edges alone cannot stop cycles.
"""
from contextlib import contextmanager

from django.contrib.auth import get_user_model
from django.db import transaction


@contextmanager
def owner_write(owner_id):
    with transaction.atomic():
        get_user_model().objects.select_for_update().get(pk=owner_id)
        yield


def record_knowledge(rabbit, previous):
    from .models import GenealogyTransition
    if previous != rabbit.genealogy_knowledge:
        GenealogyTransition.objects.create(
            rabbit=rabbit, previous=previous, current=rabbit.genealogy_knowledge,
        )
