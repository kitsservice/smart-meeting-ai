import os

from pydantic_settings import BaseSettings

_ENV_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), ".env")


class Settings(BaseSettings):
    PROJECT_NAME: str = "Smart Meeting AI"
    API_V1_STR: str = "/api/v1"

    # Supabase Configuration
    SUPABASE_URL: str = "https://dhrqllyezfwchvbeshpr.supabase.co"
    SUPABASE_KEY: str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRocnFsbHllemZ3Y2h2YmVzaHByIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMjk0MzksImV4cCI6MjEwNTgwNTQzOX0.J12NtMuLAPSPfRl1xtQLr6N887KUIKwsCfeca6qHR5I"

    # Sarvam AI Configuration (for STT)
    SARVAM_API_KEY: str = "sk_yi4qngh0_kbKjo9swzbwaYDBzpUKddCqK"

    # Deepgram Configuration (for STT and Diarization)
    DEEPGRAM_API_KEY: str = "b7640f6737a95fe71401c14e2d78bff12c77a200"

    # Gemini Configuration (for FREE Summaries)
    GEMINI_API_KEY: str = ""

    # OpenAI Configuration (Disabled to save money)
    OPENAI_API_KEY: str = ""

    class Config:
        env_file = _ENV_PATH
        extra = "ignore"


settings = Settings()
