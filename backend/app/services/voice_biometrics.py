import torch
import torchaudio
from speechbrain.inference.speaker import EncoderClassifier
from scipy.spatial.distance import cosine
import io
import soundfile as sf

class VoiceBiometricsService:
    def __init__(self):
        self._classifier = None

    @property
    def classifier(self):
        if self._classifier is None:
            print("Loading SpeechBrain Voice Biometrics Model...")
            # Load the ECAPA-TDNN model lazily
            self._classifier = EncoderClassifier.from_hparams(
                source="speechbrain/spkrec-ecapa-voxceleb",
                savedir="pretrained_models/spkrec-ecapa-voxceleb",
                run_opts={"device": "cuda" if torch.cuda.is_available() else "cpu"}
            )
        return self._classifier

    def extract_embedding_from_bytes(self, audio_bytes: bytes) -> list[float]:
        """
        Takes raw audio bytes, converts them to a 192-dimensional mathematical embedding array.
        """
        waveform, sample_rate = self._load_audio(audio_bytes)
        return self._get_embedding(waveform, sample_rate)

    def extract_embedding_from_segment(self, audio_bytes: bytes, start_sec: float, end_sec: float) -> list[float]:
        """
        Extracts an embedding from a specific time slice of the audio.
        """
        waveform, sample_rate = self._load_audio(audio_bytes)
        
        start_sample = int(start_sec * sample_rate)
        end_sample = int(end_sec * sample_rate)
        
        # Ensure we don't go out of bounds
        end_sample = min(end_sample, waveform.shape[1])
        
        sliced_waveform = waveform[:, start_sample:end_sample]
        return self._get_embedding(sliced_waveform, sample_rate)

    def _load_audio(self, audio_bytes: bytes):
        """Helper to load audio using soundfile instead of torchaudio to avoid torchcodec bug."""
        
        data, sample_rate = sf.read(io.BytesIO(audio_bytes), dtype='float32')
        # soundfile returns (frames, channels) or (frames,). 
        # torchaudio expects (channels, frames).
        if len(data.shape) == 1:
            data = data.reshape(-1, 1)
        waveform = torch.from_numpy(data).t()
        return waveform, sample_rate

    def _get_embedding(self, waveform, sample_rate) -> list[float]:
        # SpeechBrain models expect 16kHz sample rate. Resample if necessary.
        if sample_rate != 16000:
            resampler = torchaudio.transforms.Resample(orig_freq=sample_rate, new_freq=16000)
            waveform = resampler(waveform)

        # Ensure audio is mono (single channel)
        if waveform.shape[0] > 1:
            waveform = waveform.mean(dim=0, keepdim=True)

        # Generate embedding array
        embeddings = self.classifier.encode_batch(waveform)
        
        # Flatten and convert to standard python list for JSON serialization
        embedding_list = embeddings.squeeze().cpu().numpy().tolist()
        return embedding_list

    def compare_embeddings(self, emb1: list[float], emb2: list[float]) -> float:
        """
        Returns the similarity score. 
        Higher is better (1.0 is a perfect match).
        Usually, > 0.70 means it's the same person.
        """
        # scipy cosine returns distance (0 is identical). So we do 1 - distance to get similarity.
        distance = cosine(emb1, emb2)
        return 1.0 - distance

voice_biometrics = VoiceBiometricsService()
