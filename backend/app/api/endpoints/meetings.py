import asyncio
import io
import json
import logging
import os
import re
import shutil
import uuid
from pathlib import Path

import soundfile as sf
from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse
from supabase import Client

from app.core.config import settings
from app.db.supabase import get_supabase_client
from app.models.meeting import Meeting, MeetingCreate
from app.services.deepgram_service import deepgram_service
from app.services.sarvam import sarvam_service
from app.services.vector_search import process_and_store_transcript, semantic_search
from app.services.voice_biometrics import (
    get_cached_enrolled_users,
    voice_biometrics,
)

logger = logging.getLogger(__name__)
router = APIRouter()

processing_semaphore = asyncio.Semaphore(2)
TEMP_DIR = Path("temp_audio")
TEMP_DIR.mkdir(exist_ok=True)
SAVED_AUDIO_DIR = Path("saved_audio")
SAVED_AUDIO_DIR.mkdir(exist_ok=True)

RE_ROOM_CODE = re.compile(r"\[ROOM_CODE:([0-9]{6})\]")
RE_MEMBERS = re.compile(r"(\[MEMBERS:\[.*?\]\])")


def get_db() -> Client:
    try:
        return get_supabase_client()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.post("/", response_model=Meeting)
def create_meeting(meeting: MeetingCreate, db: Client = Depends(get_db)):
    """Create a new meeting record in Supabase (or update existing room session)"""
    meeting_dict = meeting.model_dump()
    desc = meeting_dict.get("description") or ""

    # If this meeting has a room code, reuse existing room record so participants remain linked
    if "[ROOM_CODE:" in desc:
        match = RE_ROOM_CODE.search(desc)
        if match:
            code = match.group(1)
            existing = (
                db.table("meetings")
                .select("id, description")
                .ilike("description", f"%[ROOM_CODE:{code}]%")
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )
            if existing.data:
                existing_id = existing.data[0]["id"]
                existing_desc = existing.data[0].get("description") or ""
                final_desc = desc
                if "[MEMBERS:" not in final_desc and "[MEMBERS:" in existing_desc:
                    mem_match = RE_MEMBERS.search(existing_desc)
                    if mem_match:
                        final_desc = f"{final_desc} {mem_match.group(1)}".strip()
                update_payload = {
                    "title": meeting_dict["title"],
                    "description": final_desc,
                }
                if meeting_dict.get("user_id"):
                    update_payload["user_id"] = meeting_dict["user_id"]

                update_res = (
                    db.table("meetings").update(update_payload).eq("id", existing_id).execute()
                )
                if update_res.data:
                    return update_res.data[0]

    data = db.table("meetings").insert(meeting_dict).execute()
    if data.data:
        return data.data[0]
    raise HTTPException(status_code=400, detail="Failed to create meeting")


@router.get("/", response_model=list[Meeting])
def get_meetings(user_id: str | None = None, db: Client = Depends(get_db)):
    """Fetch meetings either transcribed by the user or joined as a participant"""
    if not user_id or not user_id.strip():
        return []
    try:
        clean_uid = user_id.strip()
        is_uuid = False
        try:
            uuid.UUID(clean_uid)
            is_uuid = True
        except ValueError:
            is_uuid = False

        query = db.table("meetings").select(
            "id, title, description, created_at, summary, transcript, action_items, user_id"
        )
        if is_uuid:
            query = query.or_(f"user_id.eq.{clean_uid},description.ilike.%{clean_uid}%")
        else:
            query = query.ilike("description", f"%{clean_uid}%")

        data = query.order("created_at", desc=True).limit(50).execute()
        meetings = []
        for m in data.data or []:
            desc = m.get("description") or ""
            title = m.get("title") or ""
            transcript = (m.get("transcript") or "").strip()
            summary = (m.get("summary") or "").strip()

            # Exclude aborted/discarded sessions
            if "Closed before start" in desc or "Discarded by host" in desc:
                continue

            # Exclude empty room-code placeholders without transcript or summary
            if not transcript and not summary:
                if (
                    "[ROOM_CODE:" in desc
                    or title.startswith("Meeting ")
                    or title.startswith("Completed Meeting ")
                ):
                    continue

            meetings.append(m)
        return meetings
    except Exception as e:
        logger.error(f"Error fetching meetings for user {user_id}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to fetch meetings") from e


@router.get("/room-status/{room_code}")
def get_room_status(room_code: str, db: Client = Depends(get_db)):
    """Check the status of a 6-digit room code"""
    try:
        data = (
            db.table("meetings")
            .select("id, title, description, created_at")
            .ilike("description", f"%[ROOM_CODE:{room_code}]%")
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        if data.data:
            desc = data.data[0].get("description", "")
            members = []
            if "[MEMBERS:" in desc:
                try:
                    start = desc.index("[MEMBERS:") + 9
                    end = desc.find("]", start)
                    if end != -1 and end > start:
                        members = json.loads(desc[start:end])
                except Exception:
                    members = []
            status = "unknown"
            if "[STATUS:completed]" in desc:
                status = "completed"
            elif "[STATUS:active]" in desc:
                status = "active"
            elif "[STATUS:waiting]" in desc:
                status = "waiting"
            return {
                "room_code": room_code,
                "status": status,
                "participant_count": len(members),
                "participants": members,
            }
        return {
            "room_code": room_code,
            "status": "unknown",
            "participant_count": 0,
            "participants": [],
        }
    except Exception as e:
        logger.error(f"Error checking room status for {room_code}: {e}")
        return {
            "room_code": room_code,
            "status": "unknown",
            "participant_count": 0,
            "participants": [],
        }


@router.post("/room-status")
def update_room_status(payload: dict, db: Client = Depends(get_db)):
    """Update or register the status of a room code"""
    room_code = payload.get("room_code")
    status = payload.get("status", "completed")
    summary = payload.get("summary", "")
    user_id = payload.get("user_id", "00000000-0000-0000-0000-000000000000")
    if not room_code:
        raise HTTPException(status_code=400, detail="room_code required")
    try:
        data = (
            db.table("meetings")
            .select("id, description")
            .ilike("description", f"%[ROOM_CODE:{room_code}]%")
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        members_part = ""
        payload_members = payload.get("members")
        if payload_members:
            if isinstance(payload_members, list):
                members_part = f" [MEMBERS:{json.dumps(payload_members)}]"
            elif isinstance(payload_members, str):
                members_part = f" [MEMBERS:{payload_members}]"

        if data.data:
            m_id = data.data[0]["id"]
            old_desc = data.data[0].get("description", "")
            if not members_part and "[MEMBERS:" in old_desc:
                match = RE_MEMBERS.search(old_desc)
                if match:
                    members_part = f" {match.group(1)}"
            new_desc = f"[ROOM_CODE:{room_code}] [STATUS:{status}] {summary}{members_part}".strip()
            db.table("meetings").update({"description": new_desc}).eq("id", m_id).execute()
        else:
            new_desc = f"[ROOM_CODE:{room_code}] [STATUS:{status}] {summary}{members_part}".strip()
            db.table("meetings").insert(
                {
                    "title": f"Meeting {room_code}",
                    "description": new_desc,
                    "user_id": user_id,
                }
            ).execute()
        return {"status": "success", "room_code": room_code, "room_status": status}
    except Exception as e:
        logger.error(f"Error updating room status for {room_code}: {e}")
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("/{meeting_id}", response_model=Meeting)
def get_meeting(meeting_id: str, user_id: str | None = None, db: Client = Depends(get_db)):
    """Get a specific meeting by ID with security verification"""
    try:
        data = db.table("meetings").select("*").eq("id", meeting_id).execute()
        if not data.data:
            raise HTTPException(status_code=404, detail="Meeting not found")

        meeting = data.data[0]
        # Security access check: if user_id is provided, verify user is owner or participant
        if user_id and user_id.strip():
            uid = user_id.strip()
            is_owner = meeting.get("user_id") == uid
            is_participant = uid in (meeting.get("description") or "")
            if not is_owner and not is_participant:
                raise HTTPException(
                    status_code=403,
                    detail="Access denied: You are not authorized to view this meeting.",
                )

        return meeting
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching meeting {meeting_id}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to fetch meeting details") from e


@router.delete("/{meeting_id}")
def delete_meeting(meeting_id: str, db: Client = Depends(get_db)):
    """Delete a specific meeting by ID"""
    try:
        # Securely delete child records first (in case ON DELETE CASCADE is not set)
        db.table("action_items").delete().eq("meeting_id", meeting_id).execute()
        db.table("meeting_notes").delete().eq("meeting_id", meeting_id).execute()
        db.table("meeting_chunks").delete().eq("meeting_id", meeting_id).execute()
        db.table("meeting_embeddings").delete().eq("meeting_id", meeting_id).execute()
    except Exception as e:
        logger.warning(f"Error cascading deletes: {e}")

    data = db.table("meetings").delete().eq("id", meeting_id).execute()
    if data.data:
        # Clean up any recorded audio file from disk
        for ext in [".wav", ".m4a", ".mp3", ".aac", ".webm"]:
            audio_file = SAVED_AUDIO_DIR / f"{meeting_id}{ext}"
            audio_file.unlink(missing_ok=True)

        return {
            "status": "success",
            "message": "Meeting and all related data completely deleted",
        }
    raise HTTPException(status_code=404, detail="Meeting not found or could not be deleted")


async def _process_and_save_audio(meeting_id: str, file_path: str, filename: str, db: Client):
    async with processing_semaphore:
        try:
            # Read file asynchronously without blocking the event loop
            def read_file():
                with open(file_path, "rb") as f:
                    return f.read()

            audio_bytes = await run_in_threadpool(read_file)

            # 1. Transcribe with Deepgram (Includes Diarization, Timestamps, and Indic support)
            segments = await deepgram_service.transcribe_audio_with_segments(audio_bytes)

            # Fallback to Sarvam AI if Deepgram returned no segments (e.g. Indic speech / song)
            if not segments and settings.SARVAM_API_KEY:
                try:
                    logger.info("Deepgram returned no segments. Attempting Sarvam AI fallback...")
                    sarvam_text = await sarvam_service.transcribe_audio(audio_bytes)
                    if (
                        sarvam_text
                        and not sarvam_text.startswith("Error")
                        and "simulated transcript" not in sarvam_text
                        and sarvam_text.strip()
                    ):
                        audio_dur = 10.0
                        try:
                            info = sf.info(io.BytesIO(audio_bytes))
                            audio_dur = info.duration
                        except Exception:
                            pass
                        segments = [
                            {
                                "speaker_id": 0,
                                "start": 0.0,
                                "end": audio_dur,
                                "text": sarvam_text.strip(),
                            }
                        ]
                        logger.info(f"Sarvam AI fallback succeeded: {sarvam_text[:60]}")
                except Exception as fallback_err:
                    logger.warning(f"Sarvam AI fallback error: {fallback_err}")

            if not segments:
                transcript = "No speech detected."
            else:
                # 2. Extract Voice Signatures for each Speaker from the audio in a single pass
                longest_segments = {}
                for seg in segments:
                    spk_id = seg["speaker_id"]
                    duration = seg["end"] - seg["start"]
                    if (
                        spk_id not in longest_segments
                        or duration > longest_segments[spk_id]["duration"]
                    ):
                        longest_segments[spk_id] = {
                            "start": seg["start"],
                            "end": seg["end"],
                            "duration": duration,
                        }

                # Single-pass batch extraction: loads audio once into memory
                speaker_name_map = {}
                try:
                    # 1. Fetch Enrolled Users first with in-memory TTL cache
                    enrolled_users = await run_in_threadpool(get_cached_enrolled_users, db)

                    # Only run heavy neural network voice extraction if enrolled users exist
                    valid_enrolled = [
                        u
                        for u in (enrolled_users or [])
                        if u.get("voice_embedding") and len(u.get("voice_embedding") or []) == 192
                    ]

                    if valid_enrolled:
                        speaker_embeddings = await run_in_threadpool(
                            voice_biometrics.extract_embeddings_for_speaker_segments,
                            audio_bytes,
                            longest_segments,
                        )
                        speaker_name_map = await run_in_threadpool(
                            voice_biometrics.match_speakers_to_users,
                            speaker_embeddings,
                            valid_enrolled,
                        )
                except Exception as bio_err:
                    logger.warning(f"Voice biometrics matching bypassed: {bio_err}")

                # 5. Build Final Transcript with [MM:SS] timestamps for interactive seeking
                def _format_time(seconds: float) -> str:
                    total_sec = max(0, int(seconds))
                    mm = total_sec // 60
                    ss = total_sec % 60
                    return f"{mm:02d}:{ss:02d}"

                transcript_lines = []
                for seg in segments:
                    speaker_name = speaker_name_map.get(
                        seg["speaker_id"], f"Speaker {seg['speaker_id'] + 1}"
                    )
                    time_str = _format_time(seg.get("start", 0.0))
                    transcript_lines.append(f"[{time_str}] {speaker_name}: {seg['text']}")

                transcript = "\n\n".join(transcript_lines)

            # 6. Generate Summary & Action Items
            analysis = await deepgram_service.generate_summary(transcript)

            raw_action_items = analysis.get("action_items", [])
            action_items_with_ids = []
            for item in raw_action_items:
                if isinstance(item, dict):
                    action_items_with_ids.append(
                        {
                            "id": str(uuid.uuid4()),
                            "task": item.get("task", ""),
                            "assignee": item.get("assignee"),
                            "is_completed": False,
                        }
                    )
                elif isinstance(item, str):
                    action_items_with_ids.append(
                        {
                            "id": str(uuid.uuid4()),
                            "task": item,
                            "assignee": None,
                            "is_completed": False,
                        }
                    )

            # 7. Update Database
            update_data = {
                "transcript": transcript,
                "summary": analysis.get("summary", "Summary not available"),
                "action_items": action_items_with_ids,
            }

            def update_db():
                return db.table("meetings").update(update_data).eq("id", meeting_id).execute()

            await run_in_threadpool(update_db)

            # 8. Generate Embeddings for Semantic Search non-blockingly
            try:
                await process_and_store_transcript(db, meeting_id, transcript)
            except Exception as emb_err:
                logger.warning(f"Semantic search embedding generation skipped: {emb_err}")

        except Exception as e:
            logger.error(f"Error in background processing: {e}")
            try:
                def record_failure():
                    # Ensure we don't overwrite an already successful transcript
                    existing = (
                        db.table("meetings")
                        .select("transcript")
                        .eq("id", meeting_id)
                        .execute()
                    )
                    existing_t = existing.data[0].get("transcript") if existing.data else None
                    if not existing_t or existing_t in (
                        "",
                        "No speech detected.",
                        "Transcription could not be completed.",
                    ):
                        return (
                            db.table("meetings")
                            .update(
                                {
                                    "summary": (
                                        "Audio processing encountered an issue. "
                                        "Please ensure speech was recorded clearly."
                                    ),
                                    "transcript": "Transcription could not be completed.",
                                }
                            )
                            .eq("id", meeting_id)
                            .execute()
                        )

                await run_in_threadpool(record_failure)
            except Exception as update_err:
                logger.error(
                    f"Failed to record failure state for meeting {meeting_id}: {update_err}"
                )
        finally:
            # We keep the saved audio file in SAVED_AUDIO_DIR for streaming playback!
            # Only clean up files residing in TEMP_DIR.
            try:

                def cleanup_if_temp():
                    if Path(file_path).parent.resolve() == TEMP_DIR.resolve() and os.path.exists(
                        file_path
                    ):
                        os.remove(file_path)

                await run_in_threadpool(cleanup_if_temp)
            except Exception as ex:
                logger.warning(f"Failed to delete temp audio file {file_path}: {ex}")


@router.post("/{meeting_id}/process-audio")
async def process_audio(
    meeting_id: str,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    db: Client = Depends(get_db),
):
    safe_name = Path(file.filename or "audio.wav").name
    ext = Path(safe_name).suffix or ".wav"
    saved_file_path = SAVED_AUDIO_DIR / f"{meeting_id}{ext}"

    try:

        def write_buffer():
            with open(saved_file_path, "wb") as buffer:
                shutil.copyfileobj(file.file, buffer)

        await run_in_threadpool(write_buffer)
    finally:
        await file.close()

    background_tasks.add_task(
        _process_and_save_audio, meeting_id, str(saved_file_path), safe_name, db
    )

    return {"status": "success", "message": "Audio queued for processing"}


@router.get("/{meeting_id}/audio")
def get_meeting_audio(
    meeting_id: str, user_id: str | None = None, db: Client = Depends(get_db)
):
    """Streams the recorded audio for a meeting in threadpool.

    Supports HTTP range requests for audio scrubbing and playback.
    """
    if user_id and user_id.strip():
        uid = user_id.strip()
        data = db.table("meetings").select("user_id, description").eq("id", meeting_id).execute()
        if data.data:
            m = data.data[0]
            is_owner = m.get("user_id") == uid
            is_participant = uid in (m.get("description") or "")
            if not is_owner and not is_participant:
                raise HTTPException(
                    status_code=403, detail="Access denied: Not authorized for this audio"
                )

    for ext in [".wav", ".m4a", ".mp3", ".aac", ".webm"]:
        target_file = SAVED_AUDIO_DIR / f"{meeting_id}{ext}"
        if target_file.exists():
            media_type = "audio/wav" if ext == ".wav" else f"audio/{ext.lstrip('.')}"
            return FileResponse(
                path=target_file,
                media_type=media_type,
                filename=f"meeting_{meeting_id}{ext}",
            )
    raise HTTPException(status_code=404, detail="Audio recording not found for this meeting")


@router.get("/search/semantic")
async def search_meetings(query: str, user_id: str | None = None, db: Client = Depends(get_db)):
    """Performs AI Semantic Search across meetings accessible to the user (owned or joined)."""
    try:
        results = await semantic_search(db, query)
        if not user_id or not user_id.strip():
            return {"status": "success", "data": results}

        clean_uid = user_id.strip()

        def fetch_user_meetings():
            return (
                db.table("meetings")
                .select("id")
                .or_(f"user_id.eq.{clean_uid},description.ilike.%{clean_uid}%")
                .execute()
            )

        user_meetings_res = await run_in_threadpool(fetch_user_meetings)
        allowed_ids = {m["id"] for m in (user_meetings_res.data or [])}
        filtered_results = [r for r in results if r.get("meeting_id") in allowed_ids]
        return {"status": "success", "data": filtered_results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.patch("/{meeting_id}/action-items/{action_item_id}")
def update_action_item_status(
    meeting_id: str,
    action_item_id: str,
    is_completed: bool,
    db: Client = Depends(get_db),
):
    """Update the status of a specific action item"""
    res = db.table("meetings").select("action_items").eq("id", meeting_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Meeting not found")

    action_items = res.data[0].get("action_items", [])
    if not action_items:
        raise HTTPException(status_code=404, detail="No action items found for this meeting")

    item_found = False
    for item in action_items:
        if item.get("id") == action_item_id:
            item["is_completed"] = is_completed
            item_found = True
            break

    if not item_found:
        raise HTTPException(status_code=404, detail="Action item not found")

    db.table("meetings").update({"action_items": action_items}).eq("id", meeting_id).execute()

    return {
        "status": "success",
        "message": "Action item updated successfully",
        "action_item_id": action_item_id,
        "is_completed": is_completed,
    }
