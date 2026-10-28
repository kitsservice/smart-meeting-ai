import io
import logging
import time
from typing import Any

import numpy as np
import soundfile as sf
import torch

logger = logging.getLogger(__name__)

# Enrolled users cache (5-minute TTL) to avoid hitting Supabase
# for heavy 192-dim vectors on every meeting
_ENROLLED_USERS_CACHE: tuple[float, list[dict]] | None = None
_CACHE_TTL_SECONDS = 300.0


def get_cached_enrolled_users(db) -> list[dict]:
    """Retrieves enrolled users from memory cache or fetches from Supabase if expired."""
    global _ENROLLED_USERS_CACHE
    now = time.time()
    if _ENROLLED_USERS_CACHE is not None and (now - _ENROLLED_USERS_CACHE[0]) < _CACHE_TTL_SECONDS:
        return _ENROLLED_USERS_CACHE[1]

    try:
        users_res = (
            db.table("users")
            .select("id, email, full_name, voice_embedding")
            .not_.is_("voice_embedding", "null")
            .limit(200)
            .execute()
        )
        data = users_res.data or []
        _ENROLLED_USERS_CACHE = (now, data)
        return data
    except Exception as e:
        logger.warning(f"Failed to fetch enrolled users from Supabase: {e}")
        return _ENROLLED_USERS_CACHE[1] if _ENROLLED_USERS_CACHE is not None else []


def invalidate_enrolled_users_cache():
    """Invalidates cache when a user enrolls or updates their voice profile."""
    global _ENROLLED_USERS_CACHE
    _ENROLLED_USERS_CACHE = None


def format_speaker_display_name(raw_name: str | None, email: str | None = None) -> str:
    """Formats user full name or email cleanly in Title Case for meeting transcripts."""
    if raw_name and raw_name.strip():
        parts = [p.capitalize() for p in raw_name.strip().split() if p]
        if parts:
            return " ".join(parts)
    if email and email.strip():
        username = email.strip().split("@")[0].replace(".", " ").replace("_", " ").replace("-", " ")
        parts = [p.capitalize() for p in username.split() if p]
        if parts:
            return " ".join(parts)
    return "Speaker"


class VoiceBiometricsService:
    def __init__(self):
        self._classifier = None
        self._resamplers: dict[int, Any] = {}

    @property
    def classifier(self):
        if self._classifier is None:
            logger.info("Loading SpeechBrain Voice Biometrics Model...")
            try:
                from speechbrain.inference.speaker import EncoderClassifier

                # Load the ECAPA-TDNN model lazily
                self._classifier = EncoderClassifier.from_hparams(
                    source="speechbrain/spkrec-ecapa-voxceleb",
                    savedir="pretrained_models/spkrec-ecapa-voxceleb",
                    run_opts={"device": "cuda" if torch.cuda.is_available() else "cpu"},
                )
            except Exception as e:
                logger.warning(f"SpeechBrain model could not be loaded: {e}")
                return None
        return self._classifier

    def _get_resampler(self, sample_rate: int) -> Any:
        if sample_rate not in self._resamplers:
            import torchaudio

            self._resamplers[sample_rate] = torchaudio.transforms.Resample(
                orig_freq=sample_rate, new_freq=16000
            )
        return self._resamplers[sample_rate]

    def _load_and_normalize_audio(
        self, audio_input: bytes | tuple[np.ndarray, int] | torch.Tensor
    ) -> torch.Tensor:
        """Loads audio once and converts to mono 16kHz float32 tensor.
        Accepts raw bytes, (np_data, sample_rate) tuple, or torch.Tensor.
        """
        if isinstance(audio_input, torch.Tensor):
            return audio_input

        if isinstance(audio_input, tuple):
            data, sample_rate = audio_input
        else:
            try:
                data, sample_rate = sf.read(io.BytesIO(audio_input), dtype="float32")
            except Exception as sf_err:
                logger.info("soundfile failed to decode, attempting PyAV fallback: %s", sf_err)
                try:
                    import av
                    container = av.open(io.BytesIO(audio_input))
                    if not container.streams.audio:
                        raise ValueError("No audio streams found in input file.")
                    stream = container.streams.audio[0]
                    resampler = av.AudioResampler(format="flt", layout="mono", rate=16000)
                    frames = []
                    for frame in container.decode(stream):
                        for rf in resampler.resample(frame):
                            frames.append(rf.to_ndarray())
                    container.close()
                    if not frames:
                        raise ValueError("No audio frames decoded by PyAV")
                    audio_data = np.concatenate(frames, axis=1)
                    data = audio_data.T
                    sample_rate = 16000
                except Exception as av_err:
                    logger.error("Both soundfile and PyAV failed to decode audio: %s", av_err)
                    raise

        if len(data.shape) == 1:
            data = data.reshape(-1, 1)
        waveform = torch.from_numpy(data).t()

        # Resample to 16kHz if necessary (SpeechBrain ECAPA expectation)
        if sample_rate != 16000:
            resampler = self._get_resampler(sample_rate)
            waveform = resampler(waveform)

        # Ensure mono
        if waveform.shape[0] > 1:
            waveform = waveform.mean(dim=0, keepdim=True)

        return waveform

    def _compute_embedding(self, waveform: torch.Tensor) -> np.ndarray | None:
        """Computes 192-dim embedding with inference_mode to avoid gradient graphs

        and minimize memory usage. Returns NumPy array directly.
        """
        # Minimum sample requirement (0.2s at 16kHz = 3200 samples)
        if waveform.shape[1] < 3200:
            return None

        cls = self.classifier
        if cls is None:
            return None

        with torch.inference_mode():
            embeddings = cls.encode_batch(waveform)
            return embeddings.squeeze().cpu().numpy().astype(np.float32)

    def extract_embedding_from_bytes(self, audio_bytes: bytes) -> list[float]:
        """Takes raw audio bytes, converts to 192-dim embedding list for database storage."""
        waveform = self._load_and_normalize_audio(audio_bytes)
        emb = self._compute_embedding(waveform)
        return emb.tolist() if emb is not None else []

    def extract_embedding_from_segment(
        self, audio_bytes: bytes, start_sec: float, end_sec: float
    ) -> list[float]:
        """Extracts an embedding from a specific time slice."""
        waveform = self._load_and_normalize_audio(audio_bytes)
        start_sample = max(0, int(start_sec * 16000))
        end_sample = min(waveform.shape[1], int(end_sec * 16000))

        if start_sample >= end_sample:
            return []

        sliced = waveform[:, start_sample:end_sample]
        emb = self._compute_embedding(sliced)
        return emb.tolist() if emb is not None else []

    def extract_embeddings_for_speaker_segments(
        self,
        audio_input: bytes | tuple[np.ndarray, int] | torch.Tensor,
        speaker_segments: dict[int, dict],
    ) -> dict[int, np.ndarray]:
        """OPTIMIZED SINGLE-PASS EXTRACTION:

        Loads and resamples the audio file ONCE, then extracts embeddings for each
        speaker's longest segment from the shared tensor in memory.
        Returns speaker_id -> np.ndarray.
        """
        waveform = self._load_and_normalize_audio(audio_input)
        speaker_embeddings: dict[int, np.ndarray] = {}

        for spk_id, seg in speaker_segments.items():
            start_sample = max(0, int(seg["start"] * 16000))
            end_sample = min(waveform.shape[1], int(seg["end"] * 16000))

            if end_sample - start_sample < 3200:
                continue

            sliced = waveform[:, start_sample:end_sample]
            emb = self._compute_embedding(sliced)
            if emb is not None:
                speaker_embeddings[spk_id] = emb

        return speaker_embeddings

    def compare_embeddings(
        self, emb1: list[float] | np.ndarray, emb2: list[float] | np.ndarray
    ) -> float:
        """Returns cosine similarity score in [-1.0, 1.0].

        Safe against zero vectors and empty inputs. Fast numpy vectorized computation.
        """
        if emb1 is None or emb2 is None:
            return 0.0

        try:
            v1 = np.asarray(emb1, dtype=np.float32)
            v2 = np.asarray(emb2, dtype=np.float32)
            if v1.size != 192 or v2.size != 192:
                return 0.0
            norm1 = float(np.linalg.norm(v1))
            norm2 = float(np.linalg.norm(v2))
            if norm1 < 1e-9 or norm2 < 1e-9:
                return 0.0
            return float(np.dot(v1, v2) / (norm1 * norm2))
        except Exception:
            return 0.0

    def match_speakers_to_users(
        self,
        speaker_embeddings: dict[int, np.ndarray | list[float]],
        enrolled_users: list[dict],
        threshold: float = 0.20,
    ) -> dict[int, str]:
        """VECTORIZED 1-TO-1 SPEAKER IDENTIFICATION:

        Pre-stacks enrolled user embeddings into a normalized 2D matrix (N, D),
        computes cosine similarities for all speakers, and matches uniquely
        in descending order of similarity to prevent duplicate user labels.
        Displays proper full names in title case (e.g., 'Rahul Sharma').
        """
        speaker_name_map: dict[int, str] = {}
        for spk_id in speaker_embeddings:
            speaker_name_map[spk_id] = f"Speaker {spk_id + 1}"

        if not enrolled_users or not speaker_embeddings:
            return speaker_name_map

        # Filter valid enrolled users and stack embeddings into a 2D matrix
        valid_users = []
        user_vectors = []
        for u in enrolled_users:
            emb = u.get("voice_embedding")
            if emb and isinstance(emb, list) and len(emb) == 192:
                valid_users.append(u)
                user_vectors.append(emb)

        if not user_vectors:
            return speaker_name_map

        try:
            # Shape (N, 192)
            user_matrix = np.asarray(user_vectors, dtype=np.float32)
            user_norms = np.linalg.norm(user_matrix, axis=1, keepdims=True)
            user_norms = np.where(user_norms < 1e-9, 1.0, user_norms)
            normalized_user_matrix = user_matrix / user_norms

            # Filter and stack speaker embeddings into matrix (M, 192)
            valid_spk_ids: list[int] = []
            spk_vectors: list[np.ndarray] = []
            for spk_id, target_emb in speaker_embeddings.items():
                if target_emb is None:
                    continue
                v = (
                    target_emb
                    if isinstance(target_emb, np.ndarray)
                    else np.asarray(target_emb, dtype=np.float32)
                )
                if v.size == 192:
                    valid_spk_ids.append(spk_id)
                    spk_vectors.append(v.reshape(192))

            if not valid_spk_ids:
                return speaker_name_map

            spk_matrix = np.asarray(spk_vectors, dtype=np.float32)
            spk_norms = np.linalg.norm(spk_matrix, axis=1, keepdims=True)
            spk_norms = np.where(spk_norms < 1e-9, 1.0, spk_norms)
            normalized_spk_matrix = spk_matrix / spk_norms

            # Compute full similarity matrix (M, N) via a single BLAS matrix multiplication
            sim_matrix = np.dot(normalized_spk_matrix, normalized_user_matrix.T)

            # Collect candidate matches above threshold
            candidate_matches: list[tuple[float, int, int]] = []
            for s_idx, spk_id in enumerate(valid_spk_ids):
                for u_idx, score in enumerate(sim_matrix[s_idx]):
                    if score >= threshold:
                        candidate_matches.append((float(score), spk_id, u_idx))

            # Sort descending by match confidence score for optimal greedy 1-to-1 matching
            candidate_matches.sort(key=lambda x: x[0], reverse=True)

            assigned_speakers: set[int] = set()
            assigned_users: set[int] = set()

            for score, spk_id, u_idx in candidate_matches:
                if spk_id in assigned_speakers or u_idx in assigned_users:
                    continue

                matched_user = valid_users[u_idx]
                display_name = format_speaker_display_name(
                    matched_user.get("full_name"), matched_user.get("email")
                )
                speaker_name_map[spk_id] = display_name
                assigned_speakers.add(spk_id)
                assigned_users.add(u_idx)
                logger.info(
                    "Calibrated voice recognized: Speaker %d -> '%s' (similarity: %.3f)",
                    spk_id,
                    display_name,
                    score,
                )

        except Exception as e:
            logger.warning(f"Vectorized speaker matching error: {e}")

        return speaker_name_map


voice_biometrics = VoiceBiometricsService()
