import logging

from django.conf import settings
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from .serializers import ChatMessageSerializer
from .services.gemini_service import get_gemini_response

logger = logging.getLogger(__name__)


class ChatbotView(APIView):
    """
    POST /api/chatbot/
    Recibe un mensaje y retorna la respuesta del asistente IA.
    """

    authentication_classes = []
    permission_classes = []

    def post(self, request):
        serializer = ChatMessageSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        user_message = serializer.validated_data["message"]
        history = serializer.validated_data.get("history", [])

        try:
            ai_response = get_gemini_response(user_message, history)
            return Response({"response": ai_response}, status=status.HTTP_200_OK)
        except Exception as e:
            logger.exception("ChatbotView failed")
            return Response(
                {
                    "error": "No se pudo conectar con el asistente IA.",
                    "detail": str(e) if settings.DEBUG else None,
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
