from rest_framework.exceptions import APIException


class VersionConflict(APIException):
    status_code = 409
    default_code = "version_conflict"
    default_detail = "El conejo fue modificado en otro lugar."

    def __init__(self, current):
        self.current = current
        super().__init__(detail=self.default_detail)
