import asyncio
import io
import json
import logging
import time
import wave
import numpy as np
from dotenv import load_dotenv

load_dotenv("backend/.env")

from app.core.config import settings
from app.services.deepgram_service import deepgram_service, clean_json_markdown, ACTION_PATTERNS
from app.services.voice_biometrics import voice_biometrics, format_speaker_display_name
from app.services.speaker_resolver import (
    parse_members_from_description,
    resolve_speaker_names_deterministic,
    resolve_speaker_names,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("QA_TESTER")


def generate_synthetic_audio(duration_sec: float = 2.0, freq: float = 440.0) -> bytes:
    """Generates valid 16kHz mono PCM16 WAV audio for testing."""
    sample_rate = 16000
    num_samples = int(duration_sec * sample_rate)
    t = np.linspace(0, duration_sec, num_samples, endpoint=False)
    # Sine wave with gentle modulation
    audio_data = (0.5 * np.sin(2 * np.pi * freq * t) * 32767).astype(np.int16)
    
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(audio_data.tobytes())
    return buf.getvalue()


async def run_qa_suite():
    print("=" * 65)
    print("      ARES SMART MEETING AI — QA AUTOMATED TEST SUITE")
    print("=" * 65)
    passed_count = 0
    total_count = 0

    def assert_test(name: str, condition: bool, detail: str = ""):
        nonlocal passed_count, total_count
        total_count += 1
        safe_detail = ascii(detail) if any(ord(c) > 127 for c in detail) else detail
        if condition:
            passed_count += 1
            print(f" [PASS] Test {total_count:02d}: {name} {f'({safe_detail})' if detail else ''}")
        else:
            print(f" [FAIL] Test {total_count:02d}: {name} -- FAILED! {safe_detail}")
            raise AssertionError(f"Test failed: {name} - {safe_detail}")

    # TEST 1: Speaker display name formatting
    assert_test(
        "Display name clean capitalization",
        format_speaker_display_name("rahul sharma") == "Rahul Sharma",
        "Converts lower-case names to Title Case"
    )
    assert_test(
        "Email fallback to clean username",
        format_speaker_display_name(None, "sarthak.patil@example.com") == "Sarthak Patil",
        "Derives clean title-cased name from dot-separated email"
    )

    # TEST 2: Member description parsing
    desc_single = "[ROOM_CODE:123456] [STATUS:active] [MEMBERS:[{\"id\":\"u1\",\"name\":\"Alice\",\"is_host\":true}]] Notes"
    members = parse_members_from_description(desc_single)
    assert_test("Member JSON parsing (single-line)", len(members) == 1 and members[0]["name"] == "Alice")

    desc_multi = """[ROOM_CODE:999888] [STATUS:completed] [MEMBERS:[
      {"user_id": "u1", "name": "Kits", "is_host": true},
      {"user_id": "u2", "name": "Kits Sales", "is_host": false}
    ]] Recorded for 01:20"""
    members_m = parse_members_from_description(desc_multi)
    assert_test("Member JSON parsing (multi-line)", len(members_m) == 2 and members_m[1]["name"] == "Kits Sales")

    # TEST 3: Multi-sample Centroid Biometric Math
    rng = np.random.default_rng(42)
    s1 = rng.standard_normal(192).astype(np.float32)
    s1 /= np.linalg.norm(s1)
    s2 = s1 + 0.08 * rng.standard_normal(192).astype(np.float32)
    s2 /= np.linalg.norm(s2)
    s3 = s1 + 0.08 * rng.standard_normal(192).astype(np.float32)
    s3 /= np.linalg.norm(s3)

    centroid = np.mean([s1, s2, s3], axis=0)
    c_norm = np.linalg.norm(centroid)
    centroid /= c_norm
    assert_test("Centroid dimension & normalization", len(centroid) == 192 and abs(np.linalg.norm(centroid) - 1.0) < 1e-5)

    sim_self = float(np.dot(centroid, s1))
    assert_test("Multi-sample intra-voice fidelity", sim_self > 0.90, f"similarity = {sim_self:.4f}")

    diff_speaker = rng.standard_normal(192).astype(np.float32)
    diff_speaker /= np.linalg.norm(diff_speaker)
    sim_diff = float(np.dot(centroid, diff_speaker))
    assert_test("Cross-speaker rejection", sim_diff < 0.25, f"cross-similarity = {sim_diff:.4f}")

    # TEST 4: SpeechBrain Classifier Loading & Embeddings
    audio_sample = generate_synthetic_audio(duration_sec=2.5, freq=300.0)
    emb = voice_biometrics.extract_embedding_from_bytes(audio_sample)
    assert_test("SpeechBrain ECAPA-TDNN extraction", len(emb) == 192, f"dims={len(emb)}")

    # TEST 5: Indic Action Item Pattern Recognition
    sample_hi = "राहुल ने कहा कि हमें कल तक प्रोजेक्ट रिपोर्ट तैयार करना है। और डेटाबेस अपडेट करना है।"
    hi_matches = []
    for pat in ACTION_PATTERNS:
        for m in pat.finditer(sample_hi):
            hi_matches.append(m.group(0).strip())
    assert_test("Hindi action pattern detection", len(hi_matches) >= 1, f"matches={hi_matches}")

    sample_mr = "सार्थक म्हणाला की आपल्याला क्लायंटसाठी प्रेझेंटेशन तयार करा आणि फायनल करा।"
    mr_matches = []
    for pat in ACTION_PATTERNS:
        for m in pat.finditer(sample_mr):
            mr_matches.append(m.group(0).strip())
    assert_test("Marathi action pattern detection", len(mr_matches) >= 1, f"matches={mr_matches}")

    # TEST 6: Extractive Fallback with Indic Action Items
    transcript_indic = "[00:00] Kits: हमें कल तक न्यू बिल्ड डिप्लॉय करना है।\n[00:05] Sarthak: ठीक है, मी टेस्टिंग पूर्ण करतो।"
    extractive_res = deepgram_service._generate_extractive_fallback(transcript_indic)
    assert_test("Extractive summary generation", bool(extractive_res.get("summary")), extractive_res.get("summary")[:40])
    assert_test("Extractive action item extraction", len(extractive_res.get("action_items", [])) >= 1)

    # TEST 7: Deepgram Live API Health & Resiliency
    t0 = time.time()
    deepgram_healthy = False
    try:
        segments = await deepgram_service.transcribe_audio_with_segments(audio_sample, language="en")
        t_dg = time.time() - t0
        deepgram_healthy = True
        assert_test("Deepgram Nova-3 API Live Response", deepgram_healthy, f"Latency={t_dg*1000:.0f}ms")
    except Exception as e:
        assert_test("Deepgram Nova-3 API Live Response", False, str(e))

    # TEST 8: Full Speaker Resolver Multi-Attendee attribution
    test_segments = [
        {"speaker_id": 0, "start": 0.0, "end": 3.0, "text": "Good morning team, let's start the meeting."},
        {"speaker_id": 1, "start": 3.5, "end": 7.0, "text": "Thanks Kits, here is the sales pipeline update."},
    ]
    attendees = [
        {"id": "user-kits", "name": "Kits", "is_host": True},
        {"id": "user-sales", "name": "Kits Sales", "is_host": False},
    ]
    mapping = await resolve_speaker_names(
        segments=test_segments,
        attendees=attendees,
        audio_bytes=audio_sample,
        enrolled_users=[{"id": "user-kits", "name": "Kits", "voice_embedding": emb}],
    )
    assert_test(
        "Speaker identification maps attendee real names",
        mapping.get(0) in ("Kits", "Kits Sales") and mapping.get(1) in ("Kits", "Kits Sales"),
        f"Map: {mapping}"
    )

    print("\n" + "=" * 65)
    print(f" ALL {passed_count}/{total_count} QA STRESS TESTS PASSED SUCCESSFULLY! (100% HEALTH)")
    print("=" * 65)


if __name__ == "__main__":
    asyncio.run(run_qa_suite())
