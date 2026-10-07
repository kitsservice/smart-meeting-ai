import os
import sys

sys.path.append(os.getcwd())
try:
    from app.db.supabase import get_supabase_client

    db = get_supabase_client()
    res = db.table("meetings").select("id, title, transcript").execute()
    print("Total meetings:", len(res.data))
    for m in res.data:
        t = m.get("transcript")
        print(
            f"Meeting {m['title']} ({m['id']}): Transcript length = {len(t) if t else 'NONE'}"
        )
except Exception as e:
    print("Error:", e)
