import os
import sys
from unittest.mock import MagicMock

# Add backend directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.services.speaker_resolver import (
    extract_meeting_attendees,
    parse_members_from_description,
    resolve_speaker_names_deterministic,
)


def run_all_tests():
    print("--- 1. Testing parse_members_from_description (single-line) ---")
    desc1 = (
        "[ROOM_CODE:482910] [STATUS:completed] "
        '[MEMBERS:[{"user_id":"u-1","name":"Arjun Sharma","is_host":true},'
        '{"user_id":"u-2","name":"Priya Patil","is_host":false}]] Recorded for 04:12'
    )
    members1 = parse_members_from_description(desc1)
    assert len(members1) == 2, f"Expected 2 members, got {len(members1)}"
    assert members1[0]["name"] == "Arjun Sharma"
    assert members1[0]["is_host"] is True
    assert members1[1]["name"] == "Priya Patil"
    assert members1[1]["is_host"] is False
    print("[PASS] Single-line member parsing verified.")

    print("--- 2. Testing parse_members_from_description (multiline) ---")
    desc2 = """[ROOM_CODE:123456]
[STATUS:waiting]
[MEMBERS:[
  {"user_id": "u-1", "name": "Rohan Deshmukh", "is_host": true},
  {"user_id": "u-2", "name": "Ananya Joshi", "is_host": false}
]]
Recorded note"""
    members2 = parse_members_from_description(desc2)
    assert len(members2) == 2
    assert members2[0]["name"] == "Rohan Deshmukh"
    assert members2[1]["name"] == "Ananya Joshi"
    print("[PASS] Multiline member parsing verified.")

    print("--- 3. Testing parse_members_from_description (empty & missing) ---")
    assert parse_members_from_description("") == []
    assert parse_members_from_description("Direct meeting with no members tag") == []
    print("[PASS] Empty and fallback cases safely handled.")

    print("--- 4. Testing extract_meeting_attendees with Supabase metadata ---")
    mock_db = MagicMock()
    meetings_mock = MagicMock()
    users_mock = MagicMock()

    def get_table(name):
        return meetings_mock if name == "meetings" else users_mock

    mock_db.table.side_effect = get_table

    m_row = {
        "user_id": "u-host",
        "description": (
            '[MEMBERS:[{"user_id": "u-part", "name": "Vikram Singh", "is_host": false}]]'
        ),
        "title": "Strategy Session",
    }
    meetings_mock.select.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[m_row]
    )

    u_rows = [
        {
            "id": "u-host",
            "full_name": "Arjun Sharma",
            "email": "arjun@ares.ai",
            "voice_embedding": None,
        },
        {
            "id": "u-part",
            "full_name": "Vikram Singh",
            "email": "vikram@ares.ai",
            "voice_embedding": None,
        },
    ]
    users_mock.select.return_value.in_.return_value.execute.return_value = MagicMock(
        data=u_rows
    )
    users_mock.select.return_value.not_.is_.return_value.limit.return_value.execute.return_value = (
        MagicMock(data=[])
    )

    attendees, _enrolled = extract_meeting_attendees(mock_db, "test-meeting-id")
    assert len(attendees) == 2
    assert attendees[0]["is_host"] is True
    assert attendees[0]["name"] == "Arjun Sharma"
    assert attendees[1]["is_host"] is False
    assert attendees[1]["name"] == "Vikram Singh"
    print("[PASS] Meeting attendees correctly extracted with Host + Participants.")

    print("--- 5. Testing resolve_speaker_names for Single Attendee ---")
    single_att = [{"id": "u1", "name": "Arjun Sharma", "is_host": True}]
    single_segments = [
        {"speaker_id": 0, "start": 0.0, "end": 5.0, "text": "Hello world."},
        {"speaker_id": 0, "start": 5.5, "end": 10.0, "text": "Next slide."},
    ]
    res_single = resolve_speaker_names_deterministic(
        segments=single_segments, attendees=single_att
    )
    assert res_single == {0: "Arjun Sharma"}
    print("[PASS] Single attendee correctly mapped to all segments without Speaker numbers.")

    print("--- 6. Testing resolve_speaker_names for 2 Room Attendees without biometrics ---")
    two_att = [
        {"id": "u1", "name": "Arjun Sharma", "is_host": True},
        {"id": "u2", "name": "Priya Patil", "is_host": False},
    ]
    two_segments = [
        {"speaker_id": 0, "start": 0.0, "end": 4.0, "text": "Welcome Priya to the meeting."},
        {"speaker_id": 1, "start": 4.5, "end": 9.0, "text": "Thanks Arjun, glad to be here."},
    ]
    res_two = resolve_speaker_names_deterministic(
        segments=two_segments, attendees=two_att
    )
    assert res_two[0] == "Arjun Sharma", f"Expected 'Arjun Sharma', got {res_two.get(0)}"
    assert res_two[1] == "Priya Patil", f"Expected 'Priya Patil', got {res_two.get(1)}"
    print("[PASS] 2-person meeting properly mapped: 0 -> Arjun Sharma, 1 -> Priya Patil.")

    print("--- 7. Testing resolve_speaker_names with Gemini STT direct speaker_name ---")
    stt_segments = [
        {
            "speaker_id": 0,
            "speaker_name": "Arjun Sharma",
            "start": 0.0,
            "end": 4.0,
            "text": "Starting discussion.",
        },
        {
            "speaker_id": 1,
            "speaker_name": "Priya Patil",
            "start": 4.5,
            "end": 8.0,
            "text": "Reviewing data.",
        },
    ]
    res_stt = resolve_speaker_names_deterministic(
        segments=stt_segments, attendees=two_att
    )
    assert res_stt[0] == "Arjun Sharma"
    assert res_stt[1] == "Priya Patil"
    print("[PASS] Direct STT segment speaker names preserved.")

    print("--- 8. Testing resolve_speaker_names with Extra Speaker (Guest) ---")
    extra_segments = [
        {"speaker_id": 0, "start": 0.0, "end": 3.0, "text": "Host speaking."},
        {"speaker_id": 1, "start": 3.5, "end": 6.0, "text": "Participant speaking."},
        {"speaker_id": 2, "start": 6.5, "end": 9.0, "text": "Unregistered guest speaking."},
    ]
    res_extra = resolve_speaker_names_deterministic(
        segments=extra_segments, attendees=two_att
    )
    assert res_extra[0] == "Arjun Sharma"
    assert res_extra[1] == "Priya Patil"
    assert res_extra[2] == "Guest 1"
    print("[PASS] Extra speakers safely mapped to 'Guest 1' while attendees keep real names.")

    print("--- 9. Testing resolve_speaker_names when NO attendees exist ---")
    anon_segments = [
        {"speaker_id": 0, "start": 0.0, "end": 3.0, "text": "Anonymous 1"},
        {"speaker_id": 1, "start": 3.5, "end": 6.0, "text": "Anonymous 2"},
    ]
    res_anon = resolve_speaker_names_deterministic(
        segments=anon_segments, attendees=[]
    )
    assert res_anon[0] == "Speaker 1"
    assert res_anon[1] == "Speaker 2"
    print("[PASS] Fallback to 'Speaker 1', 'Speaker 2' only occurs when 0 attendees are known.")

    print("--- 10. Testing Single Attendee with Multiple Distinct Voices in Audio ---")
    single_host_att = [{"id": "u1", "name": "Arjun Sharma", "is_host": True}]
    multi_voice_segments = [
        {"speaker_id": 0, "start": 0.0, "end": 4.0, "text": "I am hosting this meeting."},
        {
            "speaker_id": 1,
            "start": 4.5,
            "end": 8.0,
            "text": "I am speaking from the other side of the room.",
        },
    ]
    res_multi = resolve_speaker_names_deterministic(
        segments=multi_voice_segments, attendees=single_host_att
    )
    assert res_multi[0] == "Arjun Sharma", f"Expected 'Arjun Sharma', got {res_multi.get(0)}"
    assert res_multi[1] == "Guest 1", f"Expected 'Guest 1', got {res_multi.get(1)}"
    print(
        "[PASS] Multi-voice audio in single-attendee room correctly preserves distinct identities!"
    )

    print("--- 11. Testing Conversational Turn Splitting for Multi-Attendee Meeting ---")
    from app.api.endpoints.meetings import _text_to_timed_segments
    conv_text = (
        "नमस्ते. आप कैसे हो? मैं ठीक हूं. और आप? मैं तो एकदम बढ़िया हूं. "
        "और आपका कैसा चल रहा है? सब कुछ अच्छा चल रहा है."
    )
    conv_segs = _text_to_timed_segments(conv_text, 15.0, num_attendees=2)
    two_attendees = [
        {"id": "u1", "name": "KITS SALES", "is_host": True},
        {"id": "u2", "name": "Kits", "is_host": False},
    ]
    res_conv = resolve_speaker_names_deterministic(conv_segs, two_attendees)
    assert res_conv[0] == "KITS SALES", f"Expected KITS SALES, got {res_conv.get(0)}"
    assert res_conv[1] == "Kits", f"Expected Kits, got {res_conv.get(1)}"
    distinct_speakers_in_segs = {s["speaker_id"] for s in conv_segs}
    assert 0 in distinct_speakers_in_segs and 1 in distinct_speakers_in_segs
    print(
        "[PASS] Conversational turn splitting verified: "
        "both attendees properly separated and attributed!"
    )

    print("\n=======================================================")
    print("ALL 11 SPEAKER IDENTIFICATION TESTS PASSED SUCCESSFULLY!")
    print("=======================================================")


if __name__ == "__main__":
    run_all_tests()
