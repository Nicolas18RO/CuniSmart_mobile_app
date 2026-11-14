from rest_framework.exceptions import APIException


class VersionConflict(APIException):
    status_code = 409
    default_code = "version_conflict"
    default_detail = "El conejo fue modificado en otro lugar."

    def __init__(self, current, detail=None):
        self.current = current
        super().__init__(detail=detail or self.default_detail)
