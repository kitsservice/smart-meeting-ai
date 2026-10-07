from supabase import Client, create_client

from app.core.config import settings

# Cached singleton instance of the client to avoid recreating on every request
_supabase_client: Client = None


def get_supabase_client() -> Client:
    global _supabase_client
    if _supabase_client is not None:
        return _supabase_client

    if not settings.SUPABASE_URL or not settings.SUPABASE_KEY:
        raise ValueError("Supabase URL and Key must be provided in the .env file")

    _supabase_client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
    return _supabase_client
