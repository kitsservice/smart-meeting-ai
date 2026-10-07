import httpx

from app.core.config import settings


class SarvamAIService:
    BASE_URL = "https://api.sarvam.ai"

    def __init__(self):
        self._client = None

    @property
    def client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(base_url=self.BASE_URL, timeout=30.0)
        return self._client

    async def transcribe_audio(
        self, audio_bytes: bytes, filename: str = "audio.wav"
    ) -> str:
        """
        Sends audio to Sarvam AI for transcription.
        Returns the transcribed text.
        """
        if not settings.SARVAM_API_KEY:
            # Fallback for local testing without an API key
            return (
                "This is a simulated transcript since no Sarvam API key was provided."
            )

        headers = {"api-subscription-key": settings.SARVAM_API_KEY}

        files = {"file": (filename, audio_bytes, "audio/wav")}
        
        # FIX: The real-time REST API does not support diarization. 
        # Sending unsupported parameters causes a 400 Bad Request.
        data = {
            "model": "saaras:v4",
            "language_code": "unknown", # Enables Auto-Detection for Hindi, English, etc.
            "mode": "transcribe"
        }

        try:
            response = await self.client.post(
                "/speech-to-text", headers=headers, files=files, data=data
            )
            response.raise_for_status()
            response_data = response.json()
            return response_data.get("transcript", "")
        except Exception as e:
            return f"Error during transcription: {e!s}"

    async def generate_summary(self, transcript: str) -> dict:
        """
        OpenAI dependency removed. Returns a static fallback for summary and action items.
        """
        return {
            "summary": "AI Summaries are currently disabled to save API costs.",
            "action_items": [],
        }


sarvam_service = SarvamAIService()
