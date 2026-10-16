import json
import logging
import re

import httpx
from fastapi.concurrency import run_in_threadpool

from app.core.config import settings

logger = logging.getLogger(__name__)

# Precompiled regular expressions for high-performance meeting parsing
RE_ASSIGNEE = re.compile(r"^([A-Z][a-zA-Z0-9_\s]+?)(?::|,|\s+please)")
ACTION_PATTERNS = [
    re.compile(r"(?:please|need to|must|should|ensure|make sure to)\s+([^.!?\n]+)", re.IGNORECASE),
    re.compile(r"(?:will|going to)\s+([^.!?\n]+)", re.IGNORECASE),
]


class DeepgramAIService:
    BASE_URL = "https://api.deepgram.com/v1/listen"

    def __init__(self):
        self._client: httpx.AsyncClient | None = None
        self._gemini_client = None

    @property
    def client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                timeout=httpx.Timeout(120.0, connect=10.0),
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

    async def _post_with_retry(self, url: str, **kwargs) -> httpx.Response:
        """Post request with automatic client reconnection if the socket dropped."""
        try:
            return await self.client.post(url, **kwargs)
        except (httpx.RemoteProtocolError, httpx.ConnectError, httpx.ReadTimeout, httpx.WriteError):
            logger.info("Deepgram connection reset, recreating HTTP client session...")
            await self.aclose()
            return await self.client.post(url, **kwargs)

    def _get_gemini_client(self):
        if self._gemini_client is None and settings.GEMINI_API_KEY:
            try:
                from google import genai

                self._gemini_client = genai.Client(api_key=settings.GEMINI_API_KEY)
            except Exception as e:
                logger.warning(f"Failed to initialize Gemini client: {e}")
        return self._gemini_client

    async def transcribe_audio_with_segments(self, audio_bytes: bytes) -> list[dict]:
        """Returns structured segment data including timestamps and speaker diarization."""
        if not settings.DEEPGRAM_API_KEY:
            raise ValueError("Deepgram API key is not configured.")

        headers = {
            "Authorization": f"Token {settings.DEEPGRAM_API_KEY}",
            "Content-Type": "audio/wav",
        }

        params = {
            "model": "nova-2",
            "smart_format": "true",
            "diarize": "true",
            "punctuate": "true",
            "detect_language": "true",  # Automatically detects Hindi, Marathi, English, etc.
        }

        response = await self._post_with_retry(
            self.BASE_URL, headers=headers, params=params, content=audio_bytes
        )
        response.raise_for_status()
        response_data = response.json()

        words = (
            response_data.get("results", {})
            .get("channels", [{}])[0]
            .get("alternatives", [{}])[0]
            .get("words", [])
        )

        if not words:
            return []

        segments = []
        current_speaker = words[0].get("speaker", 0)
        current_start = words[0].get("start", 0.0)
        current_sentence = []

        for word_obj in words:
            speaker_id = word_obj.get("speaker", 0)
            word_text = word_obj.get("punctuated_word", "")

            if speaker_id != current_speaker:
                # Save previous segment
                segments.append(
                    {
                        "speaker_id": current_speaker,
                        "start": current_start,
                        "end": word_obj.get("start", current_start + 0.1),
                        "text": " ".join(current_sentence),
                    }
                )
                # Start new segment
                current_speaker = speaker_id
                current_start = word_obj.get("start", 0.0)
                current_sentence = [word_text]
            else:
                current_sentence.append(word_text)

        if current_sentence:
            segments.append(
                {
                    "speaker_id": current_speaker,
                    "start": current_start,
                    "end": words[-1].get("end", current_start + 1.0),
                    "text": " ".join(current_sentence),
                }
            )

        return segments

    async def transcribe_audio(self, audio_bytes: bytes, filename: str = "audio.wav") -> str:
        """Sends audio to Deepgram for transcription and diarization via HTTP."""
        try:
            segments = await self.transcribe_audio_with_segments(audio_bytes)
            if not segments:
                return "No speech detected."

            transcript_lines = [f"[Speaker {seg['speaker_id']}]: {seg['text']}" for seg in segments]
            return "\n\n".join(transcript_lines)
        except Exception as e:
            logger.error(f"Deepgram Error: {e}")
            return f"Error during transcription: {e}"

    async def _generate_summary_gemini(self, transcript: str) -> dict:
        client = self._get_gemini_client()
        if client is None:
            raise ValueError("Gemini client is not initialized.")

        from google.genai import types

        prompt = f"""
You are a professional secretary and meeting analyzer.
Please analyze the following meeting transcript and provide:
1. A concise, professional summary of the meeting.
2. A list of actionable items (to-dos) discussed in the meeting, including who is responsible.

Transcript:
{transcript}

Return the result EXACTLY in this JSON format without markdown wrapping:
{{
    "summary": "String containing the summary",
    "action_items": [
        {{
            "task": "Description of the task",
            "assignee": "Name of the person responsible (or null if not specified)"
        }}
    ]
}}
"""
        last_error = None
        # Candidate active models in Google Gemini API
        for model_name in ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash"]:
            try:

                def call_gemini(target_model=model_name):
                    return client.models.generate_content(
                        model=target_model,
                        contents=prompt,
                        config=types.GenerateContentConfig(
                            response_mime_type="application/json",
                        ),
                    )

                response = await run_in_threadpool(call_gemini)
                content = response.text.strip()
                if content.startswith("```json"):
                    content = content[7:]
                elif content.startswith("```"):
                    content = content[3:]
                if content.endswith("```"):
                    content = content[:-3]
                content = content.strip()

                data = json.loads(content)
                return {
                    "summary": data.get("summary", ""),
                    "action_items": data.get("action_items", []),
                }
            except Exception as e:
                last_error = e
                err_str = str(e)
                logger.warning(f"Gemini {model_name} failed: {e}. Trying next candidate...")
                if "PERMISSION_DENIED" in err_str or "denied access" in err_str:
                    break
                continue

        raise last_error or RuntimeError("Gemini generation failed for all candidate models")

    async def _generate_summary_deepgram(self, transcript: str) -> dict:
        if not settings.DEEPGRAM_API_KEY:
            raise ValueError("Deepgram API key is not configured.")

        headers = {
            "Authorization": f"Token {settings.DEEPGRAM_API_KEY}",
            "Content-Type": "application/json",
        }
        params = {
            "summarize": "v2",
            "intents": "true",
            "topics": "true",
            "language": "en",
        }

        response = await self._post_with_retry(
            "https://api.deepgram.com/v1/read",
            headers=headers,
            params=params,
            json={"text": transcript},
        )
        response.raise_for_status()
        data = response.json()

        summary_text = data.get("results", {}).get("summary", {}).get("text", "")
        if not summary_text:
            lines = [line.strip() for line in transcript.split("\n") if line.strip()]
            summary_text = " ".join(lines[:3])

        action_items = []
        segments = data.get("results", {}).get("intents", {}).get("segments", [])
        seen_tasks = set()
        for seg in segments:
            seg_text = seg.get("text", "")
            assignee = None
            m = RE_ASSIGNEE.match(seg_text)
            if m:
                potential_name = m.group(1).strip()
                if len(potential_name) < 30:
                    assignee = potential_name

            for item in seg.get("intents", []):
                task_text = item.get("intent", "").strip()
                if task_text and task_text.lower() not in seen_tasks:
                    seen_tasks.add(task_text.lower())
                    action_items.append(
                        {
                            "task": task_text,
                            "assignee": assignee,
                        }
                    )

        # If intents did not capture tasks, extract actionable sentences directly from transcript
        if not action_items:
            for line in transcript.split("\n"):
                speaker = line.split(":")[0].strip() if ":" in line else None
                content = line.split(":", 1)[1].strip() if ":" in line else line
                for pat in ACTION_PATTERNS:
                    for m in pat.finditer(content):
                        raw_task = m.group(0).strip().capitalize()
                        if len(raw_task) > 12 and raw_task.lower() not in seen_tasks:
                            seen_tasks.add(raw_task.lower())
                            action_items.append(
                                {
                                    "task": raw_task,
                                    "assignee": speaker,
                                }
                            )
                            if len(action_items) >= 5:
                                break
                    if len(action_items) >= 5:
                        break

        return {
            "summary": summary_text,
            "action_items": action_items,
        }

    def _generate_extractive_fallback(self, transcript: str) -> dict:
        lines = [line.strip() for line in transcript.split("\n") if line.strip()]
        if not lines:
            return {"summary": "Meeting recorded with no transcript.", "action_items": []}

        summary_preview = " ".join(lines[:3])
        if len(summary_preview) > 300:
            summary_preview = summary_preview[:300] + "..."

        return {
            "summary": summary_preview,
            "action_items": [],
        }

    async def generate_summary(self, transcript: str) -> dict:
        stripped = transcript.strip() if transcript else ""
        if not stripped or len(stripped) < 10 or stripped == "No speech detected.":
            return {
                "summary": "No speech was detected in this recording.",
                "action_items": [],
            }

        # 1. Try Gemini if API key is provided
        if settings.GEMINI_API_KEY:
            try:
                result = await self._generate_summary_gemini(transcript)
                if result.get("summary"):
                    return result
            except Exception as e:
                logger.warning(f"Gemini Error ({e}). Switching to Deepgram Text Intelligence...")

        # 2. Seamless fallback to Deepgram Text Intelligence
        try:
            result = await self._generate_summary_deepgram(transcript)
            if result.get("summary"):
                return result
        except Exception as e:
            logger.error(f"Deepgram AI Summary Error: {e}")

        # 3. Clean extractive fallback
        return self._generate_extractive_fallback(transcript)


deepgram_service = DeepgramAIService()
