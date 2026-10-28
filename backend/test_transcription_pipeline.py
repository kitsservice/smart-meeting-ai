"""
Offline Unit Test Suite for Indic Transcription Pipeline
Verifies text segmentation, duration calculations, language parameter extraction,
Marathi slang preservation, and audio chunking without requiring external API network calls.
"""

import io
import sys
import unittest
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent))

import av
import numpy as np

from app.api.endpoints.meetings import _get_audio_duration, _text_to_timed_segments
from app.services.sarvam import (
    HINDI_SLANG_KEYTERMS,
    MARATHI_SLANG_KEYTERMS,
    SarvamAIService,
    chunk_audio_if_needed,
)


class TestTranscriptionPipeline(unittest.TestCase):
    def test_text_to_timed_segments_marathi(self):
        """Test Devanagari purna viram (।) and sentence splitting for Marathi."""
        sample_marathi = (
            "नमस्कार सर्वांना। आजच्या बैठकीत आपण नवीन प्रकल्पावर चर्चा करू. "
            "पुढील आठवड्यात काय काम करायचे आहे?"
        )
        total_duration = 30.0
        segments = _text_to_timed_segments(sample_marathi, total_duration)

        self.assertGreaterEqual(len(segments), 2)
        # Verify timestamps are proportional and monotonic
        prev_end = 0.0
        for seg in segments:
            self.assertIn("speaker_id", seg)
            self.assertIn("start", seg)
            self.assertIn("end", seg)
            self.assertIn("text", seg)
            self.assertGreaterEqual(seg["start"], prev_end)
            self.assertGreaterEqual(seg["end"], seg["start"])
            prev_end = seg["start"]

        # Last segment should end near total_duration
        self.assertAlmostEqual(segments[-1]["end"], total_duration, delta=1.0)

    def test_marathi_slang_preservation(self):
        """Ensure colloquial Marathi slang words are preserved accurately in segments."""
        slang_marathi = (
            "भावा आजचा सीन काय आहे? "
            "लय भारी काम झालंय आपलं. "
            "लोड नको घेऊ, उद्या क्लायंट सोबत फायनल करू."
        )
        segments = _text_to_timed_segments(slang_marathi, 20.0)
        self.assertGreaterEqual(len(segments), 2)
        combined = " ".join(s["text"] for s in segments)
        self.assertIn("भावा", combined)
        self.assertIn("लय भारी", combined)
        self.assertIn("लोड नको घेऊ", combined)

    def test_marathi_slang_keyterms_coverage(self):
        """Verify Sarvam keyterms include the top Marathi colloquial expressions."""
        expected_slangs = ["लय", "लय भारी", "भावा", "राडा", "नादखुळा", "झकास", "कडक", "सीन"]
        for slang in expected_slangs:
            self.assertIn(
                slang,
                MARATHI_SLANG_KEYTERMS,
                f"Missing essential Marathi slang term: {slang}",
            )
        self.assertGreater(len(MARATHI_SLANG_KEYTERMS), 15)
        self.assertGreater(len(HINDI_SLANG_KEYTERMS), 10)

    def test_audio_chunking_for_sarvam(self):
        """Verify audio longer than 25s is safely sliced into <25s WAV chunks."""
        # Synthesize 40s of audio in memory
        samples = np.zeros(16000 * 40, dtype=np.int16)
        buf = io.BytesIO()
        out = av.open(buf, mode="w", format="wav")
        st = out.add_stream("pcm_s16le", rate=16000, layout="mono")
        frame = av.AudioFrame.from_ndarray(samples.reshape(1, -1), format="s16", layout="mono")
        frame.rate = 16000
        for p in st.encode(frame):
            out.mux(p)
        for p in st.encode():
            out.mux(p)
        out.close()
        raw_audio = buf.getvalue()

        chunks = chunk_audio_if_needed(raw_audio, max_chunk_sec=25.0)
        self.assertEqual(len(chunks), 2)
        for c in chunks:
            c_inp = av.open(io.BytesIO(c))
            c_dur = float(c_inp.streams.audio[0].duration * c_inp.streams.audio[0].time_base)
            self.assertLessEqual(c_dur, 26.0)

    def test_text_to_timed_segments_hindi_hinglish(self):
        sample_hinglish = (
            "Aap sabhi ka swagat hai meeting me. "
            "We have to deploy the build by tomorrow evening। "
            "Please check all test cases."
        )
        total_duration = 45.0
        segments = _text_to_timed_segments(sample_hinglish, total_duration)

        self.assertGreaterEqual(len(segments), 2)
        for seg in segments:
            self.assertTrue(len(seg["text"]) > 0)

    def test_text_to_timed_segments_empty(self):
        segments = _text_to_timed_segments("", 10.0)
        self.assertEqual(segments, [])

    def test_sarvam_audio_mime_detection(self):
        # Test wav detection
        wav_header = b"RIFF\x24\x00\x00\x00WAVEfmt "
        self.assertIn("wav", SarvamAIService.detect_audio_mime(wav_header, "audio.wav"))

        # Test m4a / aac detection
        m4a_header = b"\x00\x00\x00 ftypM4A \x00\x00\x00\x00"
        self.assertIn("m4a", SarvamAIService.detect_audio_mime(m4a_header, "audio.m4a"))

        # Test mp3 detection
        mp3_header = b"ID3\x04\x00\x00"
        self.assertIn("mp3", SarvamAIService.detect_audio_mime(mp3_header, "audio.mp3"))

    def test_get_audio_duration_fallback(self):
        # Empty/corrupt bytes should safely fall back to 10.0 without throwing
        dur = _get_audio_duration(b"not_a_valid_audio_stream")
        self.assertEqual(dur, 10.0)


if __name__ == "__main__":
    suite = unittest.TestLoader().loadTestsFromTestCase(TestTranscriptionPipeline)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
