import httpx
from app.core.config import settings

class DeepgramAIService:
    BASE_URL = "https://api.deepgram.com/v1/listen"

    def __init__(self):
        self._client = None

    @property
    def client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=30.0)
        return self._client

    async def transcribe_audio_with_segments(self, audio_bytes: bytes) -> list[dict]:
        """
        Returns structured segment data including timestamps.
        """
        if not settings.DEEPGRAM_API_KEY:
            raise Exception("Deepgram API key is not configured.")

        headers = {
            "Authorization": f"Token {settings.DEEPGRAM_API_KEY}",
            "Content-Type": "audio/wav",
        }
        
        params = {
            "model": "nova-2",
            "smart_format": "true",
            "diarize": "true",
            "punctuate": "true",
            "detect_language": "true" # Enables Hindi, Marathi, English, etc.
        }

        response = await self.client.post(
            self.BASE_URL, headers=headers, params=params, content=audio_bytes
        )
        response.raise_for_status()
        response_data = response.json()
        
        words = response_data.get("results", {}).get("channels", [{}])[0].get("alternatives", [{}])[0].get("words", [])
        
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
                segments.append({
                    "speaker_id": current_speaker,
                    "start": current_start,
                    "end": word_obj.get("start", 0.0), # End when next speaker starts
                    "text": " ".join(current_sentence)
                })
                
                # Start new segment
                current_speaker = speaker_id
                current_start = word_obj.get("start", 0.0)
                current_sentence = [word_text]
            else:
                current_sentence.append(word_text)

        if current_sentence:
            segments.append({
                "speaker_id": current_speaker,
                "start": current_start,
                "end": words[-1].get("end", current_start + 1.0),
                "text": " ".join(current_sentence)
            })

        return segments

    async def transcribe_audio(self, audio_bytes: bytes, filename: str = "audio.wav") -> str:
        """
        Sends audio to Deepgram for transcription and diarization via HTTP.
        """
        try:
            segments = await self.transcribe_audio_with_segments(audio_bytes)
            if not segments:
                return "No speech detected."
                
            transcript_lines = []
            for seg in segments:
                transcript_lines.append(f"[Speaker {seg['speaker_id']}]: {seg['text']}")
                
            return "\n\n".join(transcript_lines)
            
        except Exception as e:
            print(f"Deepgram Error: {e}")
            return f"Error during transcription: {e}"

    async def generate_summary(self, transcript: str) -> dict:
        if not settings.OPENAI_API_KEY:
            return {
                "summary": "Please add OPENAI_API_KEY to your .env file to enable summaries.",
                "action_items": []
            }
            
        try:
            from openai import AsyncOpenAI
            import json

            client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
            
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
            
            response = await client.chat.completions.create(
                model='gpt-3.5-turbo',
                messages=[
                    {"role": "user", "content": prompt}
                ],
                response_format={ "type": "json_object" },
                temperature=0.7,
            )
            
            content = response.choices[0].message.content
            data = json.loads(content)
            
            return {
                "summary": data.get("summary", "Failed to parse summary"),
                "action_items": data.get("action_items", [])
            }
            
        except Exception as e:
            print(f"OpenAI Error: {e}")
            return {
                "summary": f"Failed to generate summary: {e}",
                "action_items": []
            }

deepgram_service = DeepgramAIService()
