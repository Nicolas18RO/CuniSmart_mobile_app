"""Pure reproductive rules. Calendar values are dates, never UTC instants."""
from dataclasses import dataclass
from datetime import date, timedelta


GESTATION_DAYS = 31
MAX_CALENDAR_DAYS = 366


class ReproductiveRuleError(ValueError):
    pass


@dataclass(frozen=True)
class RabbitFacts:
    uuid: str
    owner_id: int
    sex: str
    status: str
    deleted: bool


def estimated_birth_date(mating_date: date) -> date:
    if type(mating_date) is not date:
        raise ReproductiveRuleError("La fecha de monta no es válida.")
    return mating_date + timedelta(days=GESTATION_DAYS)


def validate_pair(male: RabbitFacts, female: RabbitFacts, owner_id: int) -> None:
    if male.uuid == female.uuid:
        raise ReproductiveRuleError("El macho y la hembra deben ser animales diferentes.")
    if male.owner_id != owner_id or female.owner_id != owner_id:
        raise ReproductiveRuleError("Los animales deben pertenecer al propietario autenticado.")
    if male.deleted or female.deleted or male.status != "active" or female.status != "active":
        raise ReproductiveRuleError("El evento requiere animales activos y no eliminados.")
    if male.sex != "male":
        raise ReproductiveRuleError("El macho seleccionado debe tener sexo masculino.")
    if female.sex != "female":
        raise ReproductiveRuleError("La hembra seleccionada debe tener sexo femenino.")


def validate_calendar_range(start_date: date, end_date: date) -> None:
    if type(start_date) is not date or type(end_date) is not date:
        raise ReproductiveRuleError("Las fechas inicial y final son obligatorias.")
    if start_date > end_date:
        raise ReproductiveRuleError("La fecha inicial no puede ser posterior a la fecha final.")
    if (end_date - start_date).days > MAX_CALENDAR_DAYS:
        raise ReproductiveRuleError("El rango del calendario no puede superar 366 días.")


def calendar_state(estimated: date, today: date) -> str:
    if estimated < today:
        return "OVERDUE"
    if estimated == today:
        return "DUE_TODAY"
    return "UPCOMING"
