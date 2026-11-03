import logging
from supabase import Client, create_client

from app.core.config import settings

logger = logging.getLogger(__name__)

# Cached singleton instance of the client to avoid recreating on every request
_supabase_client: Client | None = None


def get_supabase_client() -> Client:
    global _supabase_client
    if _supabase_client is not None:
        return _supabase_client

    url = (settings.SUPABASE_URL or "").strip()
    key = (settings.SUPABASE_KEY or "").strip()

    if not url or not key:
        raise ValueError(
            "SUPABASE_URL and SUPABASE_KEY must be configured in environment or .env"
        )

    _supabase_client = create_client(url, key)
    return _supabase_client
