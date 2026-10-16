import logging

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class SarvamAIService:
    BASE_URL = "https://api.sarvam.ai"

    def __init__(self):
        self._client: httpx.AsyncClient | None = None

    @property
    def client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                base_url=self.BASE_URL,
                timeout=httpx.Timeout(60.0, connect=10.0),
                limits=httpx.Limits(
                    max_keepalive_connections=20, max_connections=50, keepalive_expiry=30.0
                ),
            )
        return self._client

    async def aclose(self):
        """Close the underlying HTTP client session."""
        if self._client is not None and not self._client.is_closed:
            await self._client.aclose()
            self._client = None

    async def transcribe_audio(self, audio_bytes: bytes, filename: str = "audio.wav") -> str:
        """
        Sends audio to Sarvam AI for transcription.
        Returns the transcribed text.
        """
        if not settings.SARVAM_API_KEY:
            # Fallback for local testing without an API key
            return "This is a simulated transcript since no Sarvam API key was provided."

        headers = {"api-subscription-key": settings.SARVAM_API_KEY}
        files = {"file": (filename, audio_bytes, "audio/wav")}

        data = {
            "model": "saaras:v4",
            "language_code": "unknown",  # Enables Auto-Detection for Hindi, English, etc.
            "mode": "transcribe",
        }

        try:
            response = await self.client.post(
                "/speech-to-text", headers=headers, files=files, data=data
            )
            response.raise_for_status()
            response_data = response.json()
            return response_data.get("transcript", "")
        except Exception as e:
            logger.error(f"Sarvam AI Error: {e}")
            return f"Error during transcription: {e!s}"

    async def generate_summary(self, transcript: str) -> dict:
        """
        Summary fallback.
        """
        return {
            "summary": "AI Summaries are managed via Gemini and Deepgram Intelligence.",
            "action_items": [],
        }


sarvam_service = SarvamAIService()
