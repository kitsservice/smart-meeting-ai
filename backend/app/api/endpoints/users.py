from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from supabase import Client
from app.db.supabase import get_supabase_client
from app.services.voice_biometrics import voice_biometrics

router = APIRouter()

def get_db():
    try:
        return get_supabase_client()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/enroll-voice")
async def enroll_voice(
    user_id: str,
    full_name: str = None,
    file: UploadFile = File(...),
    db: Client = Depends(get_db)
):
    """
    Receives a 10-second audio sample from the user, generates a voice embedding, 
    and saves it to their profile in Supabase.
    """
    audio_bytes = await file.read()
    
    try:
        # 1. Generate Voice Fingerprint
        embedding = voice_biometrics.extract_embedding_from_bytes(audio_bytes)
        
        # 2. Save it to Supabase
        upsert_data = {"id": user_id, "voice_embedding": embedding}
        if full_name:
            upsert_data["full_name"] = full_name
            
        data = db.table("users").upsert(upsert_data).execute()
        
        return {"status": "success", "message": "Voice fingerprint saved successfully!"}
    
    except Exception as e:
        print(f"Error enrolling voice: {e}")
        raise HTTPException(status_code=500, detail="Failed to process voice sample.")

@router.delete("/{user_id}")
async def delete_user_account(user_id: str, db: Client = Depends(get_db)):
    """Delete a user account and all their data"""
    try:
        # Delete from public table
        db.table("users").delete().eq("id", user_id).execute()
        # Delete from auth
        db.auth.admin.delete_user(user_id)
        return {"status": "success", "message": "Account deleted successfully"}
    except Exception as e:
        print(f"Error deleting user: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete account.")
