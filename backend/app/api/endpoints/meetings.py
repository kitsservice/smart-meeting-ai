import io
import soundfile as sf
import asyncio
from app.services.sarvam import sarvam_service
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from supabase import Client

from app.db.supabase import get_supabase_client
from app.models.meeting import Meeting, MeetingCreate

router = APIRouter()


# Dependency to get db client
def get_db():
    try:
        return get_supabase_client()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/", response_model=Meeting)
def create_meeting(meeting: MeetingCreate, db: Client = Depends(get_db)):
    """Create a new meeting record in Supabase"""
    data = db.table("meetings").insert(meeting.model_dump()).execute()
    if data.data:
        return data.data[0]
    raise HTTPException(status_code=400, detail="Failed to create meeting")


@router.get("/", response_model=list[Meeting])
def get_meetings(user_id: str, db: Client = Depends(get_db)):
    """Fetch all meetings for a specific user"""
    # STRICT ISOLATION: Only fetch meetings that exactly match the logged-in user_id
    data = (
        db.table("meetings")
        .select("id, title, description, created_at, summary, user_id")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(50)
        .execute()
    )
    return data.data


@router.get("/{meeting_id}", response_model=Meeting)
def get_meeting(meeting_id: str, db: Client = Depends(get_db)):
    """Get a specific meeting by ID"""
    data = db.table("meetings").select("*").eq("id", meeting_id).execute()
    if data.data:
        return data.data[0]
    raise HTTPException(status_code=404, detail="Meeting not found")


@router.delete("/{meeting_id}")
def delete_meeting(meeting_id: str, db: Client = Depends(get_db)):
    """Delete a specific meeting by ID"""
    try:
        # Securely delete child records first (in case ON DELETE CASCADE is not set)
        db.table("action_items").delete().eq("meeting_id", meeting_id).execute()
        db.table("meeting_notes").delete().eq("meeting_id", meeting_id).execute()
        db.table("meeting_embeddings").delete().eq("meeting_id", meeting_id).execute()
    except Exception as e:
        print(f"Error cascading deletes: {e}")
        
    data = db.table("meetings").delete().eq("id", meeting_id).execute()
    if data.data:
        return {"status": "success", "message": "Meeting and all related data completely deleted"}
    raise HTTPException(
        status_code=404, detail="Meeting not found or could not be deleted"
    )


import os
import shutil
import asyncio
from pathlib import Path
import uuid
from fastapi import BackgroundTasks

processing_semaphore = asyncio.Semaphore(2)
TEMP_DIR = Path("temp_audio")
TEMP_DIR.mkdir(exist_ok=True)
from app.services.vector_search import process_and_store_transcript, semantic_search
from app.services.deepgram_service import deepgram_service
from app.services.voice_biometrics import voice_biometrics

async def _process_and_save_audio(
    meeting_id: str, file_path: str, filename: str, db: Client
):
    async with processing_semaphore:
        try:
            with open(file_path, "rb") as f:
                audio_bytes = f.read()
            # 1. Transcribe with Deepgram (Includes Diarization and Timestamps!)
            segments = await deepgram_service.transcribe_audio_with_segments(audio_bytes)
            
            if not segments:
                transcript = "No speech detected."
            else:
                # 1.5. HYBRID APPROACH: Enhance Deepgram's segments with Sarvam AI's Indic transcription
                try:
                    
                    data, samplerate = sf.read(io.BytesIO(audio_bytes))
                    
                    async def fetch_sarvam_for_segment(seg):
                        try:
                            # Add a small padding (0.2s) to avoid cutting words abruptly
                            start_sec = max(0.0, seg["start"] - 0.2)
                            end_sec = min(len(data) / samplerate, seg["end"] + 0.2)
                            
                            start_sample = int(start_sec * samplerate)
                            end_sample = int(end_sec * samplerate)
                            sliced_data = data[start_sample:end_sample]
                            
                            out_io = io.BytesIO()
                            sf.write(out_io, sliced_data, samplerate, format='WAV', subtype='PCM_16')
                            chunk_bytes = out_io.getvalue()
                            
                            text = await sarvam_service.transcribe_audio(chunk_bytes)
                            if text and not text.startswith("Error") and "simulated transcript" not in text:
                                seg["text"] = text
                        except Exception as e:
                            print(f"Sarvam segment error: {e}")
                    
                    # Run concurrently in batches of 3 to respect Sarvam rate limits
                    sarvam_sem = asyncio.Semaphore(3)
                    async def sem_fetch(seg):
                        async with sarvam_sem:
                            await fetch_sarvam_for_segment(seg)
                    
                    await asyncio.gather(*(sem_fetch(seg) for seg in segments))
                except Exception as e:
                    print(f"Hybrid Sarvam AI mapping failed: {e}")
                # 2. Extract Voice Signatures for each Speaker from the audio
                speaker_embeddings = {}
                
                # Find the longest segment for each speaker
                longest_segments = {}
                for seg in segments:
                    spk_id = seg["speaker_id"]
                    duration = seg["end"] - seg["start"]
                    if spk_id not in longest_segments or duration > longest_segments[spk_id]["duration"]:
                        longest_segments[spk_id] = {"start": seg["start"], "end": seg["end"], "duration": duration}

                # Extract embedding from the longest segment
                for spk_id, best_seg in longest_segments.items():
                    try:
                        emb = await run_in_threadpool(
                            voice_biometrics.extract_embedding_from_segment,
                            audio_bytes, best_seg["start"], best_seg["end"]
                        )
                        speaker_embeddings[spk_id] = emb
                    except Exception as e:
                        print(f"Failed to extract embedding for speaker {spk_id}: {e}")
                
                # 3. Fetch Enrolled Users from Supabase
                users_res = db.table("users").select("id, email, full_name, voice_embedding").not_.is_("voice_embedding", "null").execute()
                enrolled_users = users_res.data
                
                # 4. Match Speakers to Users
                speaker_name_map = {}
                for spk_id, target_emb in speaker_embeddings.items():
                    best_match = f"Speaker {spk_id + 1}"
                    best_score = 0.0
                    
                    for user in enrolled_users:
                        user_emb = user.get("voice_embedding")
                        if user_emb:
                            score = voice_biometrics.compare_embeddings(target_emb, user_emb)
                            if score > best_score:
                                best_score = score
                                # Extract First Name if available
                                full_name = user.get("full_name")
                                if full_name:
                                    best_match = full_name.split()[0].capitalize()
                                else:
                                    email = user.get("email")
                                    if email:
                                        best_match = email.split("@")[0].capitalize()
                    
                    # If similarity is > 0.20 (standard for mobile audio), we map the name
                    if best_score > 0.20:
                        speaker_name_map[spk_id] = best_match
                    else:
                        speaker_name_map[spk_id] = f"Speaker {spk_id + 1}"

                # 5. Build Final Transcript (Perfectly ordered by Deepgram Diarization)
                transcript_lines = []
                for seg in segments:
                    speaker_name = speaker_name_map.get(seg["speaker_id"], f"Speaker {seg['speaker_id'] + 1}")
                    transcript_lines.append(f"{speaker_name}: {seg['text']}")
                    
                transcript = "\n\n".join(transcript_lines)

            # 6. Summarize (Placeholder)
            analysis = await deepgram_service.generate_summary(transcript)

            # Process action items to add ID and is_completed
            raw_action_items = analysis.get("action_items", [])
            action_items_with_ids = []
            for item in raw_action_items:
                if isinstance(item, dict):
                    action_items_with_ids.append({
                        "id": str(uuid.uuid4()),
                        "task": item.get("task", ""),
                        "assignee": item.get("assignee"),
                        "is_completed": False
                    })
                elif isinstance(item, str):
                    action_items_with_ids.append({
                        "id": str(uuid.uuid4()),
                        "task": item,
                        "assignee": None,
                        "is_completed": False
                    })

            # 7. Update Database
            update_data = {
                "transcript": transcript,
                "summary": analysis.get("summary", "Summary not available"),
                "action_items": action_items_with_ids,
            }

            def update_db():
                return (
                    db.table("meetings").update(update_data).eq("id", meeting_id).execute()
                )

            await run_in_threadpool(update_db)
            
            # 4. Generate Embeddings for Semantic Search!
            await process_and_store_transcript(db, meeting_id, transcript)
            
        except Exception as e:
            safe_msg = str(e).encode("ascii", "ignore").decode("ascii")
            print(f"Error in background processing: {safe_msg}")


@router.post("/{meeting_id}/process-audio")
async def process_audio(
    meeting_id: str,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    db: Client = Depends(get_db),
):
    temp_file_path = TEMP_DIR / f"{uuid.uuid4()}_{file.filename}"
    with open(temp_file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    background_tasks.add_task(
        _process_and_save_audio, meeting_id, str(temp_file_path), file.filename, db
    )

    return {"status": "success", "message": "Audio queued for processing"}

@router.get("/search/semantic")
async def search_meetings(query: str, db: Client = Depends(get_db)):
    """
    Performs AI Semantic Search across all meeting transcripts.
    """
    try:
        results = await semantic_search(db, query)
        return {"status": "success", "data": results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.patch("/{meeting_id}/action-items/{action_item_id}")
def update_action_item_status(meeting_id: str, action_item_id: str, is_completed: bool, db: Client = Depends(get_db)):
    """Update the status of a specific action item"""
    # Fetch the meeting
    res = db.table("meetings").select("action_items").eq("id", meeting_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Meeting not found")
        
    action_items = res.data[0].get("action_items", [])
    if not action_items:
        raise HTTPException(status_code=404, detail="No action items found for this meeting")
        
    # Find and update the action item
    item_found = False
    for item in action_items:
        if item.get("id") == action_item_id:
            item["is_completed"] = is_completed
            item_found = True
            break
            
    if not item_found:
        raise HTTPException(status_code=404, detail="Action item not found")
        
    # Save back to database
    update_res = db.table("meetings").update({"action_items": action_items}).eq("id", meeting_id).execute()
    return {"status": "success", "message": "Action item updated successfully", "action_item_id": action_item_id, "is_completed": is_completed}
