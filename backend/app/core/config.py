import os

from pydantic_settings import BaseSettings

_ENV_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), ".env")


DEFAULT_SUPABASE_URL = "https://dhrqllyezfwchvbeshpr.supabase.co"
DEFAULT_SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRocnFsbHllemZ3Y2h2YmVzaHByIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMjk0MzksImV4cCI6MjEwNTgwNTQzOX0.J12NtMuLAPSPfRl1xtQLr6N887KUIKwsCfeca6qHR5I"
DEFAULT_SARVAM_KEY = "sk_yi4qngh0_kbKjo9swzbwaYDBzpUKddCqK"
DEFAULT_DEEPGRAM_KEY = "b7640f6737a95fe71401c14e2d78bff12c77a200"


class Settings(BaseSettings):
    PROJECT_NAME: str = "Smart Meeting AI"
    API_V1_STR: str = "/api/v1"

    # Supabase Configuration
    SUPABASE_URL: str = DEFAULT_SUPABASE_URL
    SUPABASE_KEY: str = DEFAULT_SUPABASE_KEY

    # Sarvam AI Configuration (for STT)
    SARVAM_API_KEY: str = DEFAULT_SARVAM_KEY

    # Deepgram Configuration (for STT and Diarization)
    DEEPGRAM_API_KEY: str = DEFAULT_DEEPGRAM_KEY

    # Gemini Configuration (for FREE Summaries)
    GEMINI_API_KEY: str = ""

    # OpenAI Configuration (Disabled to save money)
    OPENAI_API_KEY: str = ""

    def __init__(self, **values):
        super().__init__(**values)
        if not self.SUPABASE_URL or not self.SUPABASE_URL.strip():
            self.SUPABASE_URL = DEFAULT_SUPABASE_URL
        if not self.SUPABASE_KEY or not self.SUPABASE_KEY.strip():
            self.SUPABASE_KEY = DEFAULT_SUPABASE_KEY
        if not self.SARVAM_API_KEY or not self.SARVAM_API_KEY.strip():
            self.SARVAM_API_KEY = DEFAULT_SARVAM_KEY
        if not self.DEEPGRAM_API_KEY or not self.DEEPGRAM_API_KEY.strip():
            self.DEEPGRAM_API_KEY = DEFAULT_DEEPGRAM_KEY

    class Config:
        env_file = _ENV_PATH
        extra = "ignore"


settings = Settings()

