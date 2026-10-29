import asyncio
import io
import json
import logging

import av
import httpx
from fastapi.concurrency import run_in_threadpool

from app.core.config import settings

logger = logging.getLogger(__name__)

MARATHI_SLANG_KEYTERMS: list[str] = [
    "लय", "लय भारी", "भावा", "भाऊ", "राडा", "नाद", "नादखुळा",
    "झकास", "कडक", "खल्लास", "लोचा", "सीन", "विषय संपला",
    "चाललंय काय", "काय मग", "भिडू", "जुगाड", "कल्टी", "हवा",
    "बोंबला", "धुरळा", "एक नंबर", "load", "tension", "matter",
    "बोला की", "बरं का", "पटापट", "फायनल कर", "मित्रा", "दोस्ता",
]

HINDI_SLANG_KEYTERMS: list[str] = [
    "यार", "भाई", "जुगाड़", "बंदा", "मस्त", "scene", "bawa",
    "boss", "lafda", "chalta hai", "sahi hai", "bindass", "jhol",
    "sorted", "ek number", "funda", "tension nako", "bhaiya",
]


def chunk_audio_if_needed(audio_bytes: bytes, max_chunk_sec: float = 25.0) -> list[bytes]:
    """Slices audio into chunks under 25 seconds for Sarvam synchronous REST STT limit."""
    inp = None
    try:
        inp = av.open(io.BytesIO(audio_bytes))
        in_stream = inp.streams.audio[0]
        rate = in_stream.rate or 16000
        dur = float(in_stream.duration * in_stream.time_base) if in_stream.duration else 0.0

        if dur <= max_chunk_sec or dur == 0.0:
            return [audio_bytes]

        chunks = []
        current_out = None
        current_stream = None
        current_buf = None
        accum_samples = 0
        max_samples = int(max_chunk_sec * rate)
        layout_name = in_stream.layout.name if in_stream.layout else "mono"

        for frame in inp.decode(in_stream):
            if current_out is None:
                current_buf = io.BytesIO()
                current_out = av.open(current_buf, mode="w", format="wav")
                current_stream = current_out.add_stream(
                    "pcm_s16le", rate=rate, layout=layout_name
                )
                accum_samples = 0

            for p in current_stream.encode(frame):
                current_out.mux(p)
            accum_samples += frame.samples

            if accum_samples >= max_samples:
                for p in current_stream.encode():
                    current_out.mux(p)
                current_out.close()
                chunks.append(current_buf.getvalue())
                current_out = None

        if current_out is not None:
            for p in current_stream.encode():
                current_out.mux(p)
            current_out.close()
            chunks.append(current_buf.getvalue())

        return chunks if chunks else [audio_bytes]
    except Exception as e:
        logger.warning(f"Audio chunking skipped due to error: {e}")
        return [audio_bytes]
    finally:
        if inp is not None:
            try:
                inp.close()
            except Exception:
                pass


class SarvamAIService:
    BASE_URL = "https://api.sarvam.ai"

    def __init__(self):
        self._client: httpx.AsyncClient | None = None

    @property
    def client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                base_url=self.BASE_URL,
                timeout=httpx.Timeout(60.0, connect=10.0),
                limits=httpx.Limits(
                    max_keepalive_connections=20, max_connections=50, keepalive_expiry=30.0
                ),
            )
        return self._client

    async def aclose(self):
        """Close the underlying HTTP client session."""
        if self._client is not None and not self._client.is_closed:
            await self._client.aclose()
            self._client = None

    @staticmethod
    def detect_audio_mime(audio_bytes: bytes, filename: str = "audio.wav") -> str:
        """Dynamically detect audio MIME type from filename or header magic bytes."""
        if filename.endswith(".m4a") or (
            len(audio_bytes) > 8
            and (b"ftyp" in audio_bytes[:16] or b"moov" in audio_bytes[:32])
        ):
            return "audio/m4a"
        if (
            filename.endswith(".aac")
            or audio_bytes.startswith(b"\xff\xf1")
            or audio_bytes.startswith(b"\xff\xf9")
        ):
            return "audio/aac"
        if (
            filename.endswith(".mp3")
            or audio_bytes.startswith(b"ID3")
            or audio_bytes.startswith(b"\xff\xfb")
        ):
            return "audio/mp3"
        return "audio/wav"

    async def transcribe_audio(
        self,
        audio_bytes: bytes,
        filename: str = "audio.wav",
        language_code: str = "unknown",
    ) -> str:
        """Sends audio to Sarvam AI for transcription with Indic language and slang support.

        (Hindi, Marathi, Hinglish, etc.). Returns transcribed text.
        """
        if not settings.SARVAM_API_KEY:
            return "This is a simulated transcript since no Sarvam API key was provided."

        # Map common language names or codes to Sarvam BCP-47 identifiers
        lang_norm = (language_code or "").lower().strip()
        if "marathi" in lang_norm or lang_norm in ("mr", "mr-in"):
            bcp47 = "mr-IN"
            keyterms = MARATHI_SLANG_KEYTERMS
        elif "hindi" in lang_norm or lang_norm in ("hi", "hi-in"):
            bcp47 = "hi-IN"
            keyterms = HINDI_SLANG_KEYTERMS
        elif "english" in lang_norm or lang_norm in ("en", "en-in"):
            bcp47 = "en-IN"
            keyterms = []
        else:
            bcp47 = "unknown"
            keyterms = MARATHI_SLANG_KEYTERMS[:15] + HINDI_SLANG_KEYTERMS[:15]

        # Chunk audio non-blockingly if over 25s to avoid Sarvam REST 30s limit
        audio_chunks = await run_in_threadpool(chunk_audio_if_needed, audio_bytes, 25.0)

        # Single chunk fast-path
        if len(audio_chunks) <= 1:
            chunk_bytes = audio_chunks[0] if audio_chunks else audio_bytes
            mime = self.detect_audio_mime(chunk_bytes, filename)
            headers = {"api-subscription-key": settings.SARVAM_API_KEY}
            files = {"file": (filename, chunk_bytes, mime)}
            data = {
                "model": "saaras:v4",
                "language_code": bcp47,
                "mode": "codemix",
            }
            if keyterms:
                data["keyterms"] = json.dumps(keyterms)
            try:
                response = await self.client.post(
                    "/speech-to-text", headers=headers, files=files, data=data
                )
                response.raise_for_status()
                response_data = response.json()
                return response_data.get("transcript", "").strip()
            except Exception as e:
                logger.error(f"Sarvam AI Error: {e}")
                return f"Error during transcription: {e!s}"

        # Multi-chunk concurrent transcription via asyncio.gather (up to 3x-5x faster)
        async def _transcribe_single_chunk(idx: int, c_bytes: bytes) -> tuple[int, str]:
            chunk_filename = f"chunk_{idx}.wav"
            mime = "audio/wav"
            headers = {"api-subscription-key": settings.SARVAM_API_KEY}
            files = {"file": (chunk_filename, c_bytes, mime)}
            data = {
                "model": "saaras:v4",
                "language_code": bcp47,
                "mode": "codemix",
            }
            if keyterms:
                data["keyterms"] = json.dumps(keyterms)
            try:
                logger.info(
                    "Calling Sarvam AI STT concurrently (chunk %d/%d, lang: %s)",
                    idx + 1,
                    len(audio_chunks),
                    bcp47,
                )
                response = await self.client.post(
                    "/speech-to-text", headers=headers, files=files, data=data
                )
                response.raise_for_status()
                res_data = response.json()
                return idx, res_data.get("transcript", "").strip()
            except Exception as c_err:
                logger.error(f"Sarvam AI Error on chunk {idx}: {c_err}")
                return idx, ""

        tasks = [_transcribe_single_chunk(i, c) for i, c in enumerate(audio_chunks)]
        results = await asyncio.gather(*tasks)
        results.sort(key=lambda x: x[0])
        valid_texts = [text for _, text in results if text]
        return " ".join(valid_texts)

    async def generate_summary(self, transcript: str) -> dict:
        """
        Summary fallback.
        """
        return {
            "summary": "AI Summaries are managed via Gemini and Deepgram Intelligence.",
            "action_items": [],
        }


sarvam_service = SarvamAIService()
