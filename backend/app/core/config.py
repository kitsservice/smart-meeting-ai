from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    PROJECT_NAME: str = "Smart Meeting AI"
    API_V1_STR: str = "/api/v1"

    # Supabase Configuration
    SUPABASE_URL: str = ""
    SUPABASE_KEY: str = ""

    # Sarvam AI Configuration (for STT)
    SARVAM_API_KEY: str = ""

    # Deepgram Configuration (for STT and Diarization)
    DEEPGRAM_API_KEY: str = ""

    # Gemini Configuration (for FREE Summaries)
    GEMINI_API_KEY: str = ""

    # OpenAI Configuration (Disabled to save money)
    OPENAI_API_KEY: str = ""

    class Config:
        env_file = ".env"


settings = Settings()
