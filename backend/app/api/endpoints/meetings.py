import asyncio
import io
import json
import logging
import os
import re
import shutil
import uuid
from datetime import datetime
from pathlib import Path

import soundfile as sf
from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    HTTPException,
    UploadFile,
)
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse
from pydantic import BaseModel
from supabase import Client

from app.core.config import settings
from app.db.supabase import get_supabase_client
from app.models.meeting import Meeting, MeetingCreate
from app.services.daily_report_service import daily_report_service
from app.services.deepgram_service import deepgram_service
from app.services.sarvam import sarvam_service
from app.services.speaker_resolver import (
    extract_meeting_attendees,
    parse_members_from_description,
    resolve_speaker_names,
)
from app.services.vector_search import process_and_store_transcript, semantic_search

logger = logging.getLogger(__name__)
router = APIRouter()

processing_semaphore = asyncio.Semaphore(2)
TEMP_DIR = Path("temp_audio")
TEMP_DIR.mkdir(exist_ok=True)
SAVED_AUDIO_DIR = Path("saved_audio")
SAVED_AUDIO_DIR.mkdir(exist_ok=True)

RE_ROOM_CODE = re.compile(r"\[ROOM_CODE:([0-9]{6})\]")


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
                    old_members = parse_members_from_description(existing_desc)
                    if old_members:
                        final_desc = f"{final_desc} [MEMBERS:{json.dumps(old_members)}]".strip()
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
            members = parse_members_from_description(desc)
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
                old_members = parse_members_from_description(old_desc)
                if old_members:
                    members_part = f" [MEMBERS:{json.dumps(old_members)}]"
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


def fetch_and_filter_daily_meetings(
    db: Client, target_date: str, user_id: str | None = None
) -> list[dict]:
    """Queries Supabase synchronously for valid meetings recorded on a specific date."""
    builder = (
        db.table("meetings")
        .select(
            "id, title, description, created_at, summary, transcript, "
            "action_items, user_id"
        )
        .gte("created_at", f"{target_date}T00:00:00")
        .lte("created_at", f"{target_date}T23:59:59.999999")
    )
    if user_id and user_id.strip():
        clean_uid = user_id.strip()
        is_uuid = False
        try:
            uuid.UUID(clean_uid)
            is_uuid = True
        except ValueError:
            is_uuid = False
        if is_uuid:
            builder = builder.or_(f"user_id.eq.{clean_uid},description.ilike.%{clean_uid}%")
        else:
            builder = builder.ilike("description", f"%{clean_uid}%")

    res = builder.order("created_at", desc=False).execute()
    valid_meetings = []
    for m in (res.data or []):
        desc = str(m.get("description") or "")
        title = str(m.get("title") or "")
        transcript = str(m.get("transcript") or "").strip()
        summary = str(m.get("summary") or "").strip()

        if "Closed before start" in desc or "Discarded by host" in desc:
            continue
        if not transcript and not summary:
            if (
                "[ROOM_CODE:" in desc
                or title.startswith("Meeting ")
                or title.startswith("Completed Meeting ")
            ):
                continue
        valid_meetings.append(m)

    return valid_meetings


@router.get("/daily-report")
async def get_daily_report(
    date: str | None = None,
    user_id: str | None = None,
    db: Client = Depends(get_db),
):
    """Generates an executive daily report and short summary synthesizing

    all meetings recorded on a specific date (defaults to today).
    """
    target_date = (date or "").strip()
    if not target_date:
        target_date = datetime.now().strftime("%Y-%m-%d")
    else:
        try:
            datetime.strptime(target_date, "%Y-%m-%d")
        except ValueError as e:
            raise HTTPException(
                status_code=400,
                detail="Invalid date format. Expected YYYY-MM-DD (e.g. 2026-10-26).",
            ) from e

    try:
        valid_meetings = await run_in_threadpool(
            fetch_and_filter_daily_meetings, db, target_date, user_id
        )
        report = await daily_report_service.generate_daily_report(valid_meetings, target_date)
        return report
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error generating daily report for date {target_date}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to generate daily report") from e


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


def _get_audio_duration(audio_bytes: bytes, fallback: float = 10.0) -> float:
    """Safely extracts exact audio duration in seconds across all containers

    (M4A, AAC, MP3, WAV, WebM).
    """
    # 1. Try PyAV first (handles AAC/M4A mobile recordings seamlessly)
    try:
        import av

        with av.open(io.BytesIO(audio_bytes)) as container:
            if container.duration is not None:
                return float(container.duration) / float(av.time_base)
            if container.streams.audio and container.streams.audio[0].duration:
                stream = container.streams.audio[0]
                return float(stream.duration * stream.time_base)
    except Exception:
        pass

    # 2. Try soundfile (for standard uncompressed WAV)
    try:
        info = sf.info(io.BytesIO(audio_bytes))
        return float(info.duration)
    except Exception:
        return fallback


def _text_to_timed_segments(
    text: str, total_duration: float, speaker_id: int = 0, num_attendees: int = 1
) -> list[dict]:
    """Converts a continuous transcript into natural, proportional sentence segments
    with seekable timestamps for interactive audio scrubbing. If multiple attendees
    are registered, intelligently alternates dialogue turns on conversational cues.
    """
    clean_text = (text or "").strip()
    if not clean_text:
        return []

    # Split by Devanagari purna viram (।), periods, newlines, question/exclamation marks
    parts = re.split(r"([।\n.?!]+)", clean_text)
    raw_sentences: list[str] = []
    for i in range(0, len(parts) - 1, 2):
        s = (parts[i] + parts[i + 1]).strip()
        if s:
            raw_sentences.append(s)
    if len(parts) % 2 == 1 and parts[-1].strip():
        raw_sentences.append(parts[-1].strip())

    if not raw_sentences:
        raw_sentences = [clean_text]

    total_words = sum(max(1, len(s.split())) for s in raw_sentences)
    segments = []
    current_time = 0.0
    safe_dur = max(1.0, total_duration)

    current_spk = speaker_id
    consecutive_turns = 0

    QUESTION_CUES = (
        "?", "कैसे", "क्यों", "क्या", "कहाँ", "कब", "कितना", "कोण", "काय", "कसं", "कुठे",
        "how", "what", "why", "where", "when", "who", "which"
    )

    for s in raw_sentences:
        word_count = max(1, len(s.split()))
        fraction = word_count / total_words
        seg_duration = max(1.0, fraction * safe_dur)
        end_time = min(safe_dur, current_time + seg_duration)

        segments.append(
            {
                "speaker_id": current_spk,
                "start": round(current_time, 2),
                "end": round(end_time, 2),
                "text": s,
            }
        )
        current_time = end_time
        consecutive_turns += 1

        if num_attendees > 1:
            s_low = s.lower()
            is_question = any(q in s_low for q in QUESTION_CUES)
            if is_question or consecutive_turns >= 2:
                current_spk = (current_spk + 1) % min(num_attendees, 2)
                consecutive_turns = 0

    return segments


async def _process_and_save_audio(
    meeting_id: str,
    file_path: str,
    filename: str,
    db: Client,
    language: str | None = None,
):
    async with processing_semaphore:
        try:
            # Read file asynchronously without blocking the event loop
            def read_file():
                with open(file_path, "rb") as f:
                    return f.read()

            audio_bytes = await run_in_threadpool(read_file)
            audio_dur = await run_in_threadpool(_get_audio_duration, audio_bytes)

            # Resolve meeting attendees (host and room participants)
            meeting_attendees, enrolled_users = await run_in_threadpool(
                extract_meeting_attendees, db, meeting_id
            )
            logger.info(
                "Meeting %s attendees: %s",
                meeting_id,
                [f"{a['name']}{' (Host)' if a.get('is_host') else ''}" for a in meeting_attendees],
            )

            norm_lang = (language or "").lower().strip()
            is_marathi = "marathi" in norm_lang or norm_lang in ("mr", "mr-in")
            is_hindi = "hindi" in norm_lang or norm_lang in ("hi", "hi-in")
            is_hinglish = "hinglish" in norm_lang or "code-mixed" in norm_lang

            mime = "audio/m4a"
            is_wav = filename.endswith(".wav") or (
                audio_bytes.startswith(b"RIFF") and b"WAVE" in audio_bytes[:16]
            )
            is_mp3 = (
                filename.endswith(".mp3")
                or audio_bytes.startswith(b"ID3")
                or audio_bytes.startswith(b"\xff\xfb")
            )
            is_aac = filename.endswith(".aac") or audio_bytes.startswith(b"\xff\xf1")

            if is_wav:
                mime = "audio/wav"
            elif is_mp3:
                mime = "audio/mp3"
            elif is_aac:
                mime = "audio/aac"

            segments = []

            # 1. Specialized Indic priority path when Marathi, Hinglish, or Hindi is requested
            num_att = len(meeting_attendees)
            if is_marathi:
                logger.info(
                    "Engaging Marathi priority transcription pipeline with slang support..."
                )
                # A. Gemini Multimodal (Native Marathi street slang understanding + diarization)
                if settings.GEMINI_API_KEY:
                    try:
                        segments = await deepgram_service.transcribe_with_gemini_segments(
                            audio_bytes,
                            mime_type=mime,
                            language="mr",
                            audio_duration=audio_dur,
                            attendees=meeting_attendees,
                        )
                    except Exception as g_err:
                        logger.warning(f"Gemini Marathi error: {g_err}")

                # B. Deepgram Nova-3 (Marathi with speaker diarization)
                if not segments and settings.DEEPGRAM_API_KEY:
                    try:
                        segments = await deepgram_service.transcribe_audio_with_segments(
                            audio_bytes, language="mr"
                        )
                        if segments:
                            logger.info(
                                "Deepgram Marathi succeeded with %d segments", len(segments)
                            )
                    except Exception as dg_err:
                        logger.warning(f"Deepgram Marathi error: {dg_err}")

                # C. Sarvam AI (saaras:v4 with code-mixing & Marathi slang keyterm prompting)
                if not segments and settings.SARVAM_API_KEY:
                    try:
                        s_text = await sarvam_service.transcribe_audio(
                            audio_bytes, filename=filename, language_code="mr-IN"
                        )
                        if s_text and not s_text.startswith("Error") and len(s_text.strip()) > 3:
                            segments = _text_to_timed_segments(
                                s_text, audio_dur, num_attendees=num_att
                            )
                            logger.info(
                                "Sarvam AI Marathi transcription succeeded: %s (%d segments)",
                                s_text[:60],
                                len(segments),
                            )
                    except Exception as s_err:
                        logger.warning(f"Sarvam Marathi error: {s_err}")

            elif is_hinglish:
                logger.info("Engaging Hinglish (code-mixed) priority pipeline...")
                # A. Gemini Multimodal (Hindi-English code-switching)
                if settings.GEMINI_API_KEY:
                    try:
                        segments = await deepgram_service.transcribe_with_gemini_segments(
                            audio_bytes,
                            mime_type=mime,
                            language="hinglish",
                            audio_duration=audio_dur,
                            attendees=meeting_attendees,
                        )
                    except Exception as g_err:
                        logger.warning(f"Gemini Hinglish error: {g_err}")

                # B. Deepgram Nova-3 (Code-mixed with speaker diarization)
                if not segments and settings.DEEPGRAM_API_KEY:
                    try:
                        segments = await deepgram_service.transcribe_audio_with_segments(
                            audio_bytes, language="hi"
                        )
                        if segments:
                            logger.info(
                                "Deepgram Hinglish succeeded with %d segments", len(segments)
                            )
                    except Exception as dg_err:
                        logger.warning(f"Deepgram Hinglish error: {dg_err}")

                # C. Sarvam AI (Auto / Hindi code-mixing)
                if not segments and settings.SARVAM_API_KEY:
                    try:
                        s_text = await sarvam_service.transcribe_audio(
                            audio_bytes, filename=filename, language_code="hi-IN"
                        )
                        if s_text and not s_text.startswith("Error") and len(s_text.strip()) > 3:
                            segments = _text_to_timed_segments(
                                s_text, audio_dur, num_attendees=num_att
                            )
                    except Exception as s_err:
                        logger.warning(f"Sarvam Hinglish error: {s_err}")

            elif is_hindi:
                logger.info("Engaging Hindi priority pipeline with speaker diarization...")
                # A. Gemini Multimodal (Native Hindi comprehension + speaker diarization)
                if settings.GEMINI_API_KEY:
                    try:
                        segments = await deepgram_service.transcribe_with_gemini_segments(
                            audio_bytes,
                            mime_type=mime,
                            language="hi",
                            audio_duration=audio_dur,
                            attendees=meeting_attendees,
                        )
                    except Exception as g_err:
                        logger.warning(f"Gemini Hindi error: {g_err}")

                # B. Deepgram Nova-3 (Hindi with native speaker diarization)
                if not segments and settings.DEEPGRAM_API_KEY:
                    try:
                        segments = await deepgram_service.transcribe_audio_with_segments(
                            audio_bytes, language="hi"
                        )
                        if segments:
                            logger.info(
                                "Deepgram Hindi succeeded with %d diarized segments", len(segments)
                            )
                    except Exception as dg_err:
                        logger.warning(f"Deepgram Hindi error: {dg_err}")

                # C. Sarvam AI (Hindi Devanagari fallback if Deepgram fails)
                if not segments and settings.SARVAM_API_KEY:
                    try:
                        s_text = await sarvam_service.transcribe_audio(
                            audio_bytes, filename=filename, language_code="hi-IN"
                        )
                        if s_text and not s_text.startswith("Error") and len(s_text.strip()) > 3:
                            segments = _text_to_timed_segments(
                                s_text, audio_dur, num_attendees=num_att
                            )
                    except Exception as s_err:
                        logger.warning(f"Sarvam Hindi fallback error: {s_err}")

            else:
                # 2. General Auto-Detect Pipeline
                # A. Try Deepgram Nova-3 with auto-detection
                if settings.DEEPGRAM_API_KEY:
                    try:
                        segments = await deepgram_service.transcribe_audio_with_segments(
                            audio_bytes, language=language
                        )
                    except Exception as dg_err:
                        logger.warning(f"Deepgram auto-detect error: {dg_err}")
                        segments = []

                # Check transcript health: if Deepgram hallucinated noise or returned empty:
                words_count = sum(len(seg.get("text", "").split()) for seg in segments)
                expected_min_words = max(5, int(audio_dur * 0.35))
                is_suspicious_hallucination = (
                    audio_dur > 5.0 and words_count < expected_min_words
                ) or (not segments)

                if is_suspicious_hallucination:
                    logger.info(
                        "Deepgram output suspicious (%d words for %.1fs, expected >=%d). "
                        "Recovering speech with Gemini / Sarvam...",
                        words_count,
                        audio_dur,
                        expected_min_words,
                    )
                    indic_segments = []

                    # Try Gemini 2.0 Flash first (excels at auto-detecting Indian speech & accents)
                    if settings.GEMINI_API_KEY:
                        try:
                            indic_segments = (
                                await deepgram_service.transcribe_with_gemini_segments(
                                    audio_bytes,
                                    mime_type=mime,
                                    audio_duration=audio_dur,
                                    attendees=meeting_attendees,
                                )
                            )
                        except Exception as g_err:
                            logger.warning(f"Gemini auto-detect error: {g_err}")

                    # Try Sarvam AI Auto-Detect for Indian languages if Gemini is empty
                    if not indic_segments and settings.SARVAM_API_KEY:
                        try:
                            s_text = await sarvam_service.transcribe_audio(
                                audio_bytes, filename=filename, language_code="unknown"
                            )
                            if (
                                s_text
                                and not s_text.startswith("Error")
                                and len(s_text.strip()) > 3
                            ):
                                indic_segments = _text_to_timed_segments(
                                    s_text, audio_dur, num_attendees=num_att
                                )
                                logger.info(
                                    "Sarvam AI recovered Indic transcript: %s (%d segments)",
                                    s_text[:60],
                                    len(indic_segments),
                                )
                        except Exception as s_err:
                            logger.warning(f"Sarvam auto-detect error: {s_err}")

                    if indic_segments:
                        segments = indic_segments

            if not segments:
                transcript = "No speech detected."
            else:
                # 2. Multi-tier Speaker Identification: assigns proper attendee names
                speaker_name_map = await resolve_speaker_names(
                    segments=segments,
                    attendees=meeting_attendees,
                    audio_bytes=audio_bytes,
                    enrolled_users=enrolled_users,
                    gemini_client=deepgram_service._get_gemini_client(),
                )

                # 3. Build Final Transcript with [MM:SS] timestamps for interactive seeking
                def _format_time(seconds: float) -> str:
                    total_sec = max(0, int(seconds))
                    mm = total_sec // 60
                    ss = total_sec % 60
                    return f"{mm:02d}:{ss:02d}"

                transcript_lines = []
                for seg in segments:
                    spk_id = seg.get("speaker_id", 0)
                    speaker_name = speaker_name_map.get(
                        spk_id, f"Speaker {spk_id + 1}"
                    )
                    time_str = _format_time(seg.get("start", 0.0))
                    transcript_lines.append(f"[{time_str}] {speaker_name}: {seg.get('text', '')}")

                transcript = "\n\n".join(transcript_lines)

            # Early progressive update: persist transcript immediately to Supabase
            # so the user sees their full transcript on phone in 3 to 5 seconds!
            def update_early_transcript():
                return (
                    db.table("meetings")
                    .update(
                        {
                            "transcript": transcript,
                            "summary": "AI is analyzing meeting summary and action items...",
                        }
                    )
                    .eq("id", meeting_id)
                    .execute()
                )

            try:
                await run_in_threadpool(update_early_transcript)
            except Exception as early_err:
                logger.warning(f"Early transcript update skipped: {early_err}")

            # 6. Generate Summary & Action Items
            analysis = await deepgram_service.generate_summary(
                transcript, attendees=meeting_attendees
            )

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
    language: str | None = Form(None),
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
        _process_and_save_audio,
        meeting_id,
        str(saved_file_path),
        safe_name,
        db,
        language,
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
        if not user_id or not user_id.strip():
            results = await semantic_search(db, query)
            return {"status": "success", "data": results}

        clean_uid = user_id.strip()

        def fetch_user_meetings():
            return (
                db.table("meetings")
                .select("id")
                .or_(f"user_id.eq.{clean_uid},description.ilike.%{clean_uid}%")
                .execute()
            )

        # Run semantic search and user authorization queries concurrently for 2x speedup
        results, user_meetings_res = await asyncio.gather(
            semantic_search(db, query),
            run_in_threadpool(fetch_user_meetings),
        )
        allowed_ids = {m["id"] for m in (user_meetings_res.data or [])}
        filtered_results = [r for r in results if r.get("meeting_id") in allowed_ids]
        return {"status": "success", "data": filtered_results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


class AskMeetingRequest(BaseModel):
    query: str
    meeting_id: str | None = None
    user_id: str | None = None


@router.post("/ask")
async def ask_ares_endpoint(payload: AskMeetingRequest, db: Client = Depends(get_db)):
    """Ask Ares questions about meeting contents across transcripts, summaries, and action items."""
    query = payload.query.strip()
    if not query:
        raise HTTPException(status_code=400, detail="Query cannot be empty")

    context_parts = []
    sources = []

    # 0. Check for daily report / short summary intent
    lower_q = query.lower()
    is_daily_query = any(
        k in lower_q
        for k in [
            "daily report",
            "daily summary",
            "short summary of today",
            "today's summary",
            "today summary",
            "recap today",
            "what did we do today",
            "summary of today",
        ]
    )

    if is_daily_query and not payload.meeting_id:
        today_str = datetime.now().strftime("%Y-%m-%d")
        try:
            today_meetings = await run_in_threadpool(
                fetch_and_filter_daily_meetings, db, today_str, payload.user_id
            )

            if today_meetings:
                daily_report = await daily_report_service.generate_daily_report(
                    today_meetings, today_str
                )
                formatted_md = daily_report_service.format_daily_report_markdown(daily_report)
                today_sources = [
                    {"id": m["id"], "title": m.get("title", "Meeting")}
                    for m in today_meetings
                ]
                return {
                    "status": "success",
                    "answer": formatted_md,
                    "sources": today_sources[:4],
                    "daily_report": daily_report,
                }
            else:
                return {
                    "status": "success",
                    "answer": (
                        f"You don't have any recorded meetings for today ({today_str}) yet. "
                        "Record or join a meeting to automatically generate your daily report "
                        "and short executive summary!"
                    ),
                    "sources": [],
                }
        except Exception as e:
            logger.warning(f"Failed to compile daily report for ask query: {e}")

    # 1. If a specific meeting is targeted
    if payload.meeting_id and payload.meeting_id.strip():
        def fetch_specific():
            return (
                db.table("meetings")
                .select("id, title, summary, transcript, action_items, created_at")
                .eq("id", payload.meeting_id.strip())
                .limit(1)
                .execute()
            )

        res = await run_in_threadpool(fetch_specific)
        if res.data:
            m = res.data[0]
            sources.append({"id": m["id"], "title": m.get("title", "Meeting")})
            context_parts.append(
                f"Meeting: {m.get('title')}\n"
                f"Date: {m.get('created_at')}\n"
                f"Summary: {m.get('summary', '')}\n"
                f"Transcript:\n{str(m.get('transcript', ''))[:4000]}\n"
                f"Action Items: {m.get('action_items', [])}"
            )

    # 2. Cross-meeting search and recent meeting context (retrieved concurrently)
    if not context_parts:
        async def _safe_semantic_search():
            try:
                return await semantic_search(db, query, limit=5)
            except Exception as e:
                logger.warning(f"Semantic search failed during ask: {e}")
                return []

        def fetch_recent():
            try:
                builder = (
                    db.table("meetings")
                    .select("id, title, summary, action_items, created_at")
                    .order("created_at", desc=True)
                    .limit(8)
                )
                if payload.user_id and payload.user_id.strip():
                    uid = payload.user_id.strip()
                    builder = builder.or_(f"user_id.eq.{uid},description.ilike.%{uid}%")
                return builder.execute().data or []
            except Exception as e:
                logger.warning(f"Failed to fetch recent meetings for ask context: {e}")
                return []

        # Run semantic search and recent meetings fetch in parallel
        semantic_chunks, recent_data = await asyncio.gather(
            _safe_semantic_search(),
            run_in_threadpool(fetch_recent),
        )

        for chunk in semantic_chunks:
            chunk_text = chunk.get("chunk_text") or ""
            m_id = chunk.get("meeting_id")
            if chunk_text and m_id:
                context_parts.append(f"[Transcript excerpt from Meeting {m_id}]: {chunk_text}")
                sources.append({"id": m_id, "title": f"Meeting {m_id}"})

        for m in recent_data:
            summary = m.get("summary") or ""
            items = m.get("action_items") or []
            if summary or items:
                m_date = str(m.get("created_at", ""))[:10]
                context_parts.append(
                    f"Meeting: {m.get('title', 'Untitled')} ({m_date})\n"
                    f"Summary: {summary}\n"
                    f"Action Items: {items}"
                )
                sources.append({"id": m["id"], "title": m.get("title", "Untitled")})

    full_context = "\n\n---\n\n".join(context_parts)
    answer = await deepgram_service.ask_ares(query, full_context)

    # Deduplicate sources
    unique_sources = []
    seen = set()
    for s in sources:
        if s["id"] not in seen:
            seen.add(s["id"])
            unique_sources.append(s)

    return {
        "status": "success",
        "answer": answer,
        "sources": unique_sources[:4],
    }


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


@router.delete("/{meeting_id}/action-items/{action_item_id}")
def delete_action_item(
    meeting_id: str,
    action_item_id: str,
    db: Client = Depends(get_db),
):
    """Delete a specific action item from a meeting"""
    res = db.table("meetings").select("action_items").eq("id", meeting_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Meeting not found")

    action_items = res.data[0].get("action_items", [])
    if not action_items:
        raise HTTPException(status_code=404, detail="No action items found for this meeting")

    initial_count = len(action_items)
    filtered_items = [item for item in action_items if str(item.get("id")) != str(action_item_id)]

    if len(filtered_items) == initial_count:
        raise HTTPException(status_code=404, detail="Action item not found")

    db.table("meetings").update({"action_items": filtered_items}).eq("id", meeting_id).execute()

    return {
        "status": "success",
        "message": "Action item deleted successfully",
        "action_item_id": action_item_id,
    }
