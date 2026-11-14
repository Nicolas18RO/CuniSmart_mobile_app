import base64
import json
import uuid

from django.utils import timezone
from rest_framework import serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .genealogy import assign_or_update, build_pedigree, clear_parent, public_link
from .kinship import evaluate
from .models import Rabbit, SensorReading
from .genealogy_herd import herd_for_owner
from .serializers import RabbitSerializer, ReproductiveEventWriteSerializer, SensorReadingSerializer
from .genealogy_transactions import owner_write
from .reproductive_domain import ReproductiveRuleError
from .reproductive_service import ReproductiveEventService
from .r3_sync_http import IdempotencyKeyConflict, r3_idempotent
from .sync_receipts import ReceiptKeyConflict
from .parentlink_replacement import replace_parent_link


class RabbitViewSet(viewsets.ModelViewSet):
    serializer_class = RabbitSerializer
    permission_classes = [IsAuthenticated]
    lookup_value_regex = r"[^/]+"

    def update(self, request, *args, **kwargs):
        with owner_write(request.user.pk):
            return super().update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        with owner_write(request.user.pk):
            return super().destroy(request, *args, **kwargs)

    def get_queryset(self):
        return Rabbit.objects.filter(
            user=self.request.user,
            deleted_at__isnull=True,
        ).order_by("-created_at")

    def get_object(self):
        queryset = self.filter_queryset(self.get_queryset())
        raw = self.kwargs[self.lookup_field]
        rabbit = self._find_rabbit(queryset, raw)
        if rabbit is None:
            raise NotFound()
        self.check_object_permissions(self.request, rabbit)
        return rabbit

    def _find_rabbit(self, queryset, raw):
        parsed = None
        try:
            parsed = uuid.UUID(str(raw))
        except (ValueError, AttributeError, TypeError):
            parsed = None
        if parsed is not None:
            found = queryset.filter(uuid=parsed).first()
            if found is not None:
                return found
        if str(raw).isdigit():
            return queryset.filter(pk=int(raw)).first()
        return None

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    def perform_destroy(self, instance):
        if instance.deleted_at is None:
            try:
                ReproductiveEventService().assert_rabbit_mutation_allowed(
                    instance, deleting=True,
                )
            except ReproductiveRuleError as error:
                raise ValidationError(str(error))
            instance.deleted_at = timezone.now()
            instance.version = instance.version + 1
            instance.save(update_fields=["deleted_at", "version", "updated_at"])


def _own_active_rabbit(user, raw):
    try:
        parsed = uuid.UUID(str(raw))
    except (ValueError, TypeError, AttributeError):
        raise ValidationError("El identificador del animal es obligatorio.")
    rabbit = Rabbit.objects.filter(
        user=user,
        uuid=parsed,
        deleted_at__isnull=True,
    ).first()
    if rabbit is None:
        raise NotFound()
    return rabbit


def _optional_version(data):
    if not isinstance(data, dict) or "version" not in data or data.get("version") is None:
        return None
    value = data.get("version")
    if type(value) is not int or not 1 <= value <= 2147483647:
        raise ValidationError("La versión no es válida.")
    return value


class PedigreeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, rabbit_uuid):
        animal = _own_active_rabbit(request.user, rabbit_uuid)
        payload = build_pedigree(animal)
        herd = herd_for_owner(request.user)
        projected = herd.get(str(animal.uuid))
        individual = None
        if projected and projected.father and projected.mother:
            parents = evaluate(projected.father, projected.mother, herd)
            parent_payload = parents.to_payload()
            individual = {
                "status": parents.status,
                "coefficient": parent_payload["expectedInbreeding"],
                "minimumKnownCoefficient": parent_payload["minimumKnownInbreeding"],
                "isExact": parents.is_exact,
                "riskLevel": parents.risk_level,
                "warnings": list(parents.warnings),
            }
        payload["individualInbreeding"] = individual
        return Response(payload)


class ParentLinkView(APIView):
    permission_classes = [IsAuthenticated]

    @r3_idempotent("PARENT_LINK", "CREATE", "UPDATE")
    def put(self, request, rabbit_uuid, role):
        if not isinstance(request.data, dict):
            raise ValidationError("Se requiere un objeto JSON.")
        child = _own_active_rabbit(request.user, rabbit_uuid)
        parent = _own_active_rabbit(request.user, request.data.get("parent_uuid"))
        link = assign_or_update(
            child=child,
            parent=parent,
            role=str(role),
            version=_optional_version(request.data),
        )
        return Response(public_link(link))

    @r3_idempotent("PARENT_LINK", "DELETE")
    def delete(self, request, rabbit_uuid, role):
        if not isinstance(request.data, dict):
            raise ValidationError("Se requiere un objeto JSON.")
        child = _own_active_rabbit(request.user, rabbit_uuid)
        link = clear_parent(
            child=child,
            role=str(role),
            version=_optional_version(request.data),
        )
        return Response(public_link(link))

    def post(self, request, rabbit_uuid, role):
        if request.headers.get("X-CuniSmart-Sync-Version") != "2" or \
                request.headers.get("X-CuniSmart-Sync-Action") != "PARENTLINK_REPLACE":
            raise ValidationError("Unsupported sync version or action.")
        key = request.headers.get("Idempotency-Key")
        try:
            operation_uuid = uuid.UUID(key or "")
            previous = request.data["previous"]
            replacement = request.data["replacement"]
            previous_cycle = uuid.UUID(previous["cycleUuid"])
            parent_uuid = uuid.UUID(replacement["parent_uuid"])
            expected = previous["expectedVersion"]
        except (KeyError, TypeError, ValueError, AttributeError):
            raise ValidationError("Invalid replacement payload.") from None
        try:
            receipt = replace_parent_link(
                owner=request.user, child_uuid=rabbit_uuid, role=role,
                previous_cycle_uuid=previous_cycle, expected_version=expected,
                parent_uuid=parent_uuid, operation_uuid=operation_uuid,
            )
        except ReceiptKeyConflict:
            raise IdempotencyKeyConflict() from None
        evidence = {
            "receiptId": receipt.pk, "ownerId": receipt.owner_id,
            "operationUuid": str(receipt.operation_uuid),
            "requestHash": receipt.request_hash,
            "entityType": receipt.entity_type, "action": receipt.action,
            "contractVersion": receipt.contract_version,
            "remoteIdentity": receipt.remote_identity,
            "remoteVersion": receipt.remote_version,
            "statusCode": receipt.status_code,
            "bodyPresent": receipt.body_present,
            "confirmedAt": receipt.confirmed_at.isoformat(),
        }
        header = base64.urlsafe_b64encode(
            json.dumps(evidence, separators=(",", ":")).encode()
        ).decode("ascii")
        return Response(receipt.response_body, status=receipt.status_code,
                        headers={"X-CuniSmart-Sync-Receipt": header})


_herd_for = herd_for_owner


class KinshipView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        left = _own_active_rabbit(request.user, request.query_params.get("a"))
        right = _own_active_rabbit(request.user, request.query_params.get("b"))
        mode = request.query_params.get("mode", "relationship")
        if mode not in ("relationship", "breeding"):
            raise ValidationError("El modo de evaluación no es válido.")
        if mode == "breeding":
            if left.pk == right.pk or {left.sex, right.sex} != {"male", "female"}:
                raise ValidationError("El cruce requiere un macho y una hembra distintos.")
            if left.status != "active" or right.status != "active":
                raise ValidationError("El cruce requiere animales activos.")
        result = evaluate(str(left.uuid), str(right.uuid), _herd_for(request.user))
        return Response(result.to_payload())


class SensorReadingViewSet(viewsets.ModelViewSet):
    queryset = SensorReading.objects.select_related("rabbit", "sensor_device").all()
    serializer_class = SensorReadingSerializer


class ReproductiveEventViewSet(viewsets.ViewSet):
    permission_classes = [IsAuthenticated]
    lookup_value_regex = r"[0-9a-fA-F-]{36}"
    service_class = ReproductiveEventService

    def _service(self):
        return self.service_class()

    def _validated(self, request, *, partial=False):
        if not isinstance(request.data, dict):
            raise ValidationError("Se requiere un objeto JSON.")
        serializer = ReproductiveEventWriteSerializer(data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        return serializer.validated_data

    def list(self, request):
        service = self._service()
        return Response(service.list_payloads(request.user.pk))

    def retrieve(self, request, pk=None):
        service = self._service()
        event = service.get(request.user.pk, pk)
        if event is None:
            raise NotFound()
        return Response(service.full_payload(event))

    @r3_idempotent("REPRODUCTIVE_EVENT", "CREATE")
    def create(self, request):
        data = self._validated(request)
        required = {"male_uuid", "female_uuid", "mating_date"}
        if not required.issubset(data):
            raise ValidationError("Macho, hembra y fecha de monta son obligatorios.")
        if "version" in data:
            raise ValidationError("La versión es administrada por el servidor.")
        try:
            event = self._service().create(owner_id=request.user.pk, **data)
        except ReproductiveRuleError as error:
            raise ValidationError(str(error))
        return Response(self._service().full_payload(event), status=status.HTTP_201_CREATED)

    @r3_idempotent("REPRODUCTIVE_EVENT")
    def update(self, request, pk=None):
        return self._update(request, pk, partial=False)

    @r3_idempotent("REPRODUCTIVE_EVENT", "UPDATE")
    def partial_update(self, request, pk=None):
        return self._update(request, pk, partial=True)

    def _update(self, request, pk, partial):
        data = self._validated(request, partial=partial)
        if "male_uuid" in data or "female_uuid" in data:
            raise ValidationError("Los animales del evento no se pueden reemplazar.")
        if "version" not in data:
            raise ValidationError("La versión es obligatoria para actualizar.")
        if not partial and "mating_date" not in data:
            raise ValidationError("La fecha de monta es obligatoria.")
        try:
            event = self._service().update(
                owner_id=request.user.pk, event_uuid=pk,
                version=data.pop("version"), **data,
            )
        except ReproductiveRuleError as error:
            raise ValidationError(str(error))
        if event is None:
            raise NotFound()
        return Response(self._service().full_payload(event))

    @r3_idempotent("REPRODUCTIVE_EVENT", "DELETE")
    def destroy(self, request, pk=None):
        raw = request.data.get("version") if isinstance(request.data, dict) else None
        if raw is None:
            raw = request.query_params.get("version")
            if isinstance(raw, str) and raw.isdigit():
                raw = int(raw)
        if type(raw) is not int or not 1 <= raw <= 2147483647:
            raise ValidationError("La versión es obligatoria para eliminar.")
        event = self._service().delete(owner_id=request.user.pk, event_uuid=pk, version=raw)
        if event is None:
            raise NotFound()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=False, methods=["get"])
    def calendar(self, request):
        date_parser = serializers.DateField()
        try:
            start_date = date_parser.run_validation(request.query_params.get("start_date"))
            end_date = date_parser.run_validation(request.query_params.get("end_date"))
            rows = self._service().calendar(
                owner_id=request.user.pk, start_date=start_date, end_date=end_date,
            )
        except ReproductiveRuleError as error:
            raise ValidationError(str(error))
        return Response({"start_date": start_date, "end_date": end_date, "events": rows})
