import os

from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), ".env")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_ENV_PATH,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    PROJECT_NAME: str = "Smart Meeting AI"
    API_V1_STR: str = "/api/v1"

    # Supabase Configuration (loaded from .env or environment variables)
    SUPABASE_URL: str = ""
    SUPABASE_KEY: str = ""

    # Sarvam AI Configuration (loaded from .env or environment variables)
    SARVAM_API_KEY: str = ""

    # Deepgram Configuration (loaded from .env or environment variables)
    DEEPGRAM_API_KEY: str = ""

    # Gemini Configuration (loaded from .env or environment variables)
    GEMINI_API_KEY: str = ""

    # OpenAI Configuration (loaded from .env or environment variables)
    OPENAI_API_KEY: str = ""


settings = Settings()
