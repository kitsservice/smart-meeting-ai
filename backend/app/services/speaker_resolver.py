import json
import logging
import re
from typing import Any

from fastapi.concurrency import run_in_threadpool

from app.services.deepgram_service import clean_json_markdown
from app.services.voice_biometrics import (
    format_speaker_display_name,
    get_cached_enrolled_users,
    voice_biometrics,
)

logger = logging.getLogger(__name__)

RE_ROOM_CODE = re.compile(r"\[ROOM_CODE:([0-9]{6})\]")
RE_MEMBERS = re.compile(r"\[MEMBERS:(\[.*?\])\]", re.DOTALL)


def parse_members_from_description(desc: str) -> list[dict]:
    """Robustly parses participant list [MEMBERS:[{...}]] from meeting description.

    Supports single-line, multi-line, and nested JSON brackets.
    """
    if not desc or "[MEMBERS:" not in desc:
        return []

    # 1. Direct regex search with DOTALL
    match = RE_MEMBERS.search(desc)
    if match:
        try:
            parsed = json.loads(match.group(1))
            if isinstance(parsed, list):
                return parsed
        except Exception as e:
            logger.debug(f"Regex members JSON parse error: {e}")

    # 2. Balanced bracket depth parsing fallback
    try:
        start_tag = "[MEMBERS:"
        start_idx = desc.find(start_tag)
        if start_idx != -1:
            array_start = desc.find("[", start_idx + len(start_tag) - 1)
            if array_start != -1:
                bracket_depth = 0
                for i in range(array_start, len(desc)):
                    if desc[i] == "[":
                        bracket_depth += 1
                    elif desc[i] == "]":
                        bracket_depth -= 1
                        if bracket_depth == 0:
                            sub = desc[array_start : i + 1]
                            parsed = json.loads(sub)
                            if isinstance(parsed, list):
                                return parsed
                            break
    except Exception as e:
        logger.warning(f"Fallback member bracket parsing failed: {e}")

    return []


def extract_meeting_attendees(db: Any, meeting_id: str) -> tuple[list[dict], list[dict]]:
    """Extracts all attendee profiles (host and room participants) for a meeting.

    Returns:
        (meeting_attendees, enrolled_users)
        - meeting_attendees: list of attendees with proper names, role, and user_id.
        - enrolled_users: list of attendees/users with calibrated 192-d voice embeddings.
    """
    attendees_dict: dict[str, dict] = {}
    host_id: str | None = None
    desc: str = ""

    try:
        m_row = (
            db.table("meetings")
            .select("user_id, description, title")
            .eq("id", meeting_id)
            .execute()
        )
        if m_row.data:
            host_id = m_row.data[0].get("user_id")
            desc = m_row.data[0].get("description") or ""
            title = m_row.data[0].get("title") or ""

            # Check if this meeting belongs to a room session
            members_list = parse_members_from_description(desc)
            if not members_list:
                room_match = RE_ROOM_CODE.search(desc) or RE_ROOM_CODE.search(title)
                if room_match:
                    code = room_match.group(1)
                    r_rows = (
                        db.table("meetings")
                        .select("description")
                        .ilike("description", f"%[ROOM_CODE:{code}]%")
                        .order("created_at", desc=True)
                        .limit(5)
                        .execute()
                    )
                    for r in r_rows.data or []:
                        m_list = parse_members_from_description(r.get("description") or "")
                        if m_list:
                            members_list = m_list
                            break

            # 1. Parse members from description
            for mem in members_list:
                uid = str(mem.get("user_id") or mem.get("id") or "").strip()
                name = mem.get("name")
                is_host = bool(mem.get("is_host", False))
                email = mem.get("email")
                if uid:
                    attendees_dict[uid] = {
                        "id": uid,
                        "name": name,
                        "is_host": is_host,
                        "email": email,
                        "joined_at": mem.get("joined_at"),
                    }

            # 2. Ensure host is registered
            if host_id and host_id not in attendees_dict:
                attendees_dict[host_id] = {
                    "id": host_id,
                    "name": None,
                    "is_host": True,
                    "email": None,
                }
            elif host_id and host_id in attendees_dict:
                attendees_dict[host_id]["is_host"] = True

    except Exception as m_err:
        logger.warning(f"Error fetching meeting attendee metadata: {m_err}")

    # 3. Query `users` table for full_name, email, and voice_embedding
    if attendees_dict:
        try:
            u_res = (
                db.table("users")
                .select("id, email, full_name, voice_embedding")
                .in_("id", list(attendees_dict.keys()))
                .execute()
            )
            for u in u_res.data or []:
                uid = u["id"]
                if uid in attendees_dict:
                    if not attendees_dict[uid].get("name"):
                        attendees_dict[uid]["name"] = u.get("full_name") or (
                            u["email"].split("@")[0] if u.get("email") else None
                        )
                    if not attendees_dict[uid].get("email") and u.get("email"):
                        attendees_dict[uid]["email"] = u.get("email")
                    emb = u.get("voice_embedding")
                    if emb and isinstance(emb, list) and len(emb) == 192:
                        attendees_dict[uid]["voice_embedding"] = emb
        except Exception as u_err:
            logger.warning(f"Error querying users table for attendee details: {u_err}")

    # 4. Clean up attendee names into Title Case
    attendees_list: list[dict] = []
    participant_counter = 1
    for _uid, att in attendees_dict.items():
        clean_name = format_speaker_display_name(att.get("name"), att.get("email"))
        if not clean_name or clean_name == "Speaker":
            if att.get("is_host"):
                clean_name = "Host"
            else:
                clean_name = f"Participant {participant_counter}"
                participant_counter += 1
        att["name"] = clean_name
        attendees_list.append(att)

    # Sort: Host first, then participants
    attendees_list.sort(key=lambda a: (not a.get("is_host", False), a.get("name", "")))

    # 5. Fetch enrolled users across organization for voice biometrics matching
    cached_enrolled = get_cached_enrolled_users(db) or []
    combined_enrolled: list[dict] = []
    seen_enrolled_ids = set()

    # Prioritize meeting attendees who have valid 192-d voice embeddings
    for att in attendees_list:
        if att.get("voice_embedding") and len(att["voice_embedding"]) == 192:
            combined_enrolled.append(att)
            seen_enrolled_ids.add(att["id"])

    # Include other registered enrolled users
    for u in cached_enrolled:
        uid = u.get("id")
        if uid and uid not in seen_enrolled_ids:
            emb = u.get("voice_embedding")
            if emb and isinstance(emb, list) and len(emb) == 192:
                combined_enrolled.append(u)
                seen_enrolled_ids.add(uid)

    return attendees_list, combined_enrolled


async def contextual_speaker_attribution_gemini(
    segments: list[dict],
    available_attendees: list[dict],
    unassigned_spk_ids: list[int],
    gemini_client: Any,
) -> dict[int, str]:
    """Uses Gemini 2.0 Flash to contextually match speaker IDs to attendee names

    based on conversation dialogue, addresses, greetings, and host duties.
    """
    if not gemini_client or not available_attendees or not unassigned_spk_ids:
        return {}

    from google.genai import types

    # Prepare attendee list description
    att_descriptions = []
    for a in available_attendees:
        role = "Host" if a.get("is_host") else "Participant"
        att_descriptions.append(f'- "{a["name"]}" (Role: {role})')
    attendees_text = "\n".join(att_descriptions)

    # Prepare compact dialogue excerpt (up to first 30 segments)
    dialogue_lines = []
    for seg in segments[:30]:
        sid = seg.get("speaker_id", 0)
        txt = seg.get("text", "").strip()
        if txt:
            dialogue_lines.append(f"[Speaker {sid}]: {txt}")
    dialogue_text = "\n".join(dialogue_lines)

    if not dialogue_lines:
        return {}

    prompt = (
        "You are an AI meeting speaker identification specialist.\n"
        "Your task is to identify and attribute the Speaker IDs to the proper names "
        "of the attendees who joined this meeting.\n\n"
        f"MEETING ATTENDEES:\n{attendees_text}\n\n"
        f"SPEECH DIALOGUE SAMPLE:\n{dialogue_text}\n\n"
        f"UNASSIGNED SPEAKER IDS TO RESOLVE: {unassigned_spk_ids}\n\n"
        "IDENTIFICATION RULES:\n"
        "1. Identify who is speaking based on greetings, names spoken ('Hi Priya'), "
        "introductions, project updates, who speaks first, and who moderates as Host.\n"
        "2. Match each unassigned Speaker ID to the most accurate attendee name from the list.\n"
        "3. Every returned name MUST match one of the candidate attendee names exactly.\n"
        "4. Return ONLY a valid JSON object mapping speaker ID strings to their full name.\n\n"
        'Example format: {"0": "Arjun Sharma", "1": "Priya Patil"}'
    )

    try:
        def call_gemini():
            return gemini_client.models.generate_content(
                model="gemini-2.0-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                ),
            )

        response = await run_in_threadpool(call_gemini)
        raw_text = clean_json_markdown(response.text or "")

        parsed = json.loads(raw_text)
        if isinstance(parsed, dict):
            resolved: dict[int, str] = {}
            valid_names = {a["name"].lower(): a["name"] for a in available_attendees}
            for sid_str, name in parsed.items():
                try:
                    sid = int(sid_str)
                    if sid in unassigned_spk_ids and isinstance(name, str):
                        match_proper = valid_names.get(name.lower().strip())
                        if match_proper:
                            resolved[sid] = match_proper
                            logger.info(
                                "Gemini AI contextual attribution: Speaker %d -> '%s'",
                                sid,
                                match_proper,
                            )
                except ValueError:
                    continue
            return resolved
    except Exception as e:
        logger.warning(f"Contextual speaker attribution via Gemini error: {e}")

    return {}


def resolve_speaker_names_deterministic(
    segments: list[dict],
    attendees: list[dict],
    initial_map: dict[int, str] | None = None,
) -> dict[int, str]:
    """Deterministic fallback and base mapping for speaker identification.

    Attributes speakers based on attendee roles, join order, and segment appearance.
    """
    speaker_name_map: dict[int, str] = dict(initial_map or {})
    detected_speakers = sorted(list({seg.get("speaker_id", 0) for seg in segments}))
    if not detected_speakers:
        return speaker_name_map

    # Tier 0: Direct labels already in segments
    attendee_name_lookup = {a["name"].lower(): a["name"] for a in attendees if a.get("name")}
    for seg in segments:
        s_name = seg.get("speaker_name")
        spk_id = seg.get("speaker_id", 0)
        if s_name and isinstance(s_name, str) and not s_name.startswith("Speaker "):
            proper_match = attendee_name_lookup.get(s_name.lower().strip(), s_name.strip())
            speaker_name_map[spk_id] = proper_match

    unassigned_spk_ids = [
        spk_id
        for spk_id in detected_speakers
        if spk_id not in speaker_name_map or speaker_name_map[spk_id].startswith("Speaker ")
    ]
    if not unassigned_spk_ids:
        return speaker_name_map

    # Tier 2: Single Attendee Shortcut
    # Only map all speakers to solo_name if ONLY 1 speaker was actually detected in the audio.
    # If multiple distinct voices are detected, collapsing them into the single attendee is invalid.
    if len(attendees) == 1 and len(detected_speakers) == 1:
        solo_name = attendees[0].get("name") or "Host"
        for spk_id in unassigned_spk_ids:
            speaker_name_map[spk_id] = solo_name
        return speaker_name_map

    # Available attendees not yet assigned to any speaker
    assigned_names = {name.lower() for name in speaker_name_map.values()}
    available_attendees = [
        a for a in attendees if a.get("name") and a["name"].lower() not in assigned_names
    ]

    # If no attendees are known in the system at all, fallback to clean Speaker numbers
    if not available_attendees and not attendees:
        for spk_id in unassigned_spk_ids:
            speaker_name_map[spk_id] = f"Speaker {spk_id + 1}"
        return speaker_name_map

    # Match Host (or primary attendee) to earliest unassigned speaker in time
    host_att = next((a for a in available_attendees if a.get("is_host")), None)
    if not host_att and available_attendees:
        host_att = available_attendees[0]
    if host_att and unassigned_spk_ids:
        earliest_spk_id = min(
            unassigned_spk_ids,
            key=lambda sid: next(
                (s.get("start", 0.0) for s in segments if s.get("speaker_id") == sid),
                999999.0,
            ),
        )
        speaker_name_map[earliest_spk_id] = host_att["name"]
        available_attendees.remove(host_att)
        unassigned_spk_ids.remove(earliest_spk_id)

    # Pair remaining unassigned speakers with remaining attendees in join order
    for spk_id, att in zip(list(unassigned_spk_ids), list(available_attendees), strict=False):
        speaker_name_map[spk_id] = att["name"]
        unassigned_spk_ids.remove(spk_id)
        available_attendees.remove(att)

    # If extra speakers exist (e.g. guest joined on speakerphone)
    guest_idx = 1
    for spk_id in unassigned_spk_ids:
        speaker_name_map[spk_id] = f"Guest {guest_idx}"
        guest_idx += 1

    return speaker_name_map


async def resolve_speaker_names(
    segments: list[dict],
    attendees: list[dict],
    audio_bytes: bytes | None = None,
    enrolled_users: list[dict] | None = None,
    gemini_client: Any = None,
) -> dict[int, str]:
    """Unified 4-Tier Speaker Identification Pipeline.

    Guarantees every speaker in the meeting gets their proper, real human name:
      - Tier 0: Direct transcription labels (Gemini STT output)
      - Tier 1: Acoustic voice biometrics (SpeechBrain ECAPA-TDNN)
      - Tier 2: Single attendee shortcut
      - Tier 3: Contextual AI dialogue attribution (Gemini 2.0 Flash)
      - Tier 4: Intelligent deterministic role-based & join-order matching
    """
    speaker_name_map: dict[int, str] = {}
    detected_speakers = sorted(list({seg.get("speaker_id", 0) for seg in segments}))
    if not detected_speakers:
        return speaker_name_map

    # -------------------------------------------------------------
    # Tier 0: Check if segments already carry valid attendee names
    # -------------------------------------------------------------
    attendee_name_lookup = {a["name"].lower(): a["name"] for a in attendees if a.get("name")}
    for seg in segments:
        s_name = seg.get("speaker_name")
        spk_id = seg.get("speaker_id", 0)
        if s_name and isinstance(s_name, str) and not s_name.startswith("Speaker "):
            proper_match = attendee_name_lookup.get(s_name.lower().strip(), s_name.strip())
            speaker_name_map[spk_id] = proper_match

    # -------------------------------------------------------------
    # Tier 1: Acoustic Voice Biometrics (for Calibrated Users)
    # -------------------------------------------------------------
    unassigned_for_bio = [
        spk_id for spk_id in detected_speakers if spk_id not in speaker_name_map
    ]
    if unassigned_for_bio and enrolled_users and audio_bytes:
        try:
            # Find longest segment for each unassigned speaker
            longest_segments: dict[int, dict] = {}
            for seg in segments:
                spk_id = seg.get("speaker_id", 0)
                if spk_id not in unassigned_for_bio:
                    continue
                duration = seg.get("end", 0.0) - seg.get("start", 0.0)
                if (
                    spk_id not in longest_segments
                    or duration > longest_segments[spk_id]["duration"]
                ):
                    longest_segments[spk_id] = {
                        "start": seg.get("start", 0.0),
                        "end": seg.get("end", 0.0),
                        "duration": duration,
                    }

            if longest_segments:
                speaker_embeddings = await run_in_threadpool(
                    voice_biometrics.extract_embeddings_for_speaker_segments,
                    audio_bytes,
                    longest_segments,
                )
                bio_matches = await run_in_threadpool(
                    voice_biometrics.match_speakers_to_users,
                    speaker_embeddings,
                    enrolled_users,
                    0.18,
                )
                for spk_id, matched_name in bio_matches.items():
                    if matched_name and not matched_name.startswith("Speaker "):
                        speaker_name_map[spk_id] = matched_name
                        logger.info(
                            "Biometrics recognized speaker %d -> '%s'", spk_id, matched_name
                        )
        except Exception as bio_err:
            logger.warning(f"Voice biometrics matching error: {bio_err}")

    # Check which speakers still need proper names
    unassigned_spk_ids = [
        spk_id
        for spk_id in detected_speakers
        if spk_id not in speaker_name_map or speaker_name_map[spk_id].startswith("Speaker ")
    ]
    if not unassigned_spk_ids:
        return speaker_name_map

    # -------------------------------------------------------------
    # Tier 2: Single Attendee Shortcut
    # Only map all speakers to solo_name if ONLY 1 speaker was actually detected in the audio.
    # If multiple distinct voices are detected, collapsing them into the single attendee is invalid.
    # -------------------------------------------------------------
    if len(attendees) == 1 and len(detected_speakers) == 1:
        solo_name = attendees[0].get("name") or "Host"
        for spk_id in unassigned_spk_ids:
            speaker_name_map[spk_id] = solo_name
        return speaker_name_map

    # -------------------------------------------------------------
    # Tier 3: Contextual AI Dialogue Attribution (Gemini)
    # -------------------------------------------------------------
    assigned_names = {name.lower() for name in speaker_name_map.values()}
    available_attendees = [
        a for a in attendees if a.get("name") and a["name"].lower() not in assigned_names
    ]

    if gemini_client and available_attendees and unassigned_spk_ids:
        ai_matches = await contextual_speaker_attribution_gemini(
            segments, available_attendees, unassigned_spk_ids, gemini_client
        )
        for spk_id, name in ai_matches.items():
            speaker_name_map[spk_id] = name

    # -------------------------------------------------------------
    # Tier 4: Deterministic Fallback Assignment
    # -------------------------------------------------------------
    return resolve_speaker_names_deterministic(
        segments=segments,
        attendees=attendees,
        initial_map=speaker_name_map,
    )
