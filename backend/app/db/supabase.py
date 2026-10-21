from supabase import Client, create_client

from app.core.config import settings

# Cached singleton instance of the client to avoid recreating on every request
_supabase_client: Client | None = None


def get_supabase_client() -> Client:
    global _supabase_client
    if _supabase_client is not None:
        return _supabase_client

    url = (settings.SUPABASE_URL or "").strip()
    key = (settings.SUPABASE_KEY or "").strip()

    if not url or not key:
        from app.core.config import DEFAULT_SUPABASE_KEY, DEFAULT_SUPABASE_URL
        url = url or DEFAULT_SUPABASE_URL
        key = key or DEFAULT_SUPABASE_KEY

    _supabase_client = create_client(url, key)
    return _supabase_client

