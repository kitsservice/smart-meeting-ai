import logging
import threading

from fastapi.concurrency import run_in_threadpool

logger = logging.getLogger(__name__)

_embedding_model = None
_model_lock = threading.Lock()


def get_embedding_model():
    global _embedding_model
    if _embedding_model is None:
        with _model_lock:
            if _embedding_model is None:
                try:
                    import torch
                    # Restrict PyTorch to single-thread CPU execution to prevent
                    # thread pool contention and high memory spikes
                    torch.set_num_threads(1)
                    from sentence_transformers import SentenceTransformer

                    # all-MiniLM-L6-v2 produces 384-dimensional vectors. Fast and lightweight.
                    _embedding_model = SentenceTransformer("all-MiniLM-L6-v2", device="cpu")
                except ImportError as e:
                    msg = (
                        "sentence-transformers is not installed. "
                        "Run: pip install sentence-transformers"
                    )
                    raise RuntimeError(msg) from e
    return _embedding_model


def chunk_text(text: str, chunk_size: int = 500, overlap: int = 50) -> list[str]:
    """
    Splits a long transcript into overlapping chunks to ensure context is preserved.
    """
    words = text.split()
    if not words:
        return []

    chunks = []
    i = 0
    step = max(1, chunk_size - overlap)
    while i < len(words):
        chunk = " ".join(words[i : i + chunk_size])
        chunks.append(chunk)
        i += step
    return chunks


async def process_and_store_transcript(supabase_client, meeting_id: str, transcript: str):
    """
    Chunks a transcript, generates embeddings in a worker thread, and saves them to Supabase.
    Runs encoding non-blockingly via run_in_threadpool.
    """
    if not transcript or len(transcript.strip()) < 10:
        return

    model = await run_in_threadpool(get_embedding_model)
    chunks = chunk_text(transcript)
    if not chunks:
        return

    # Non-blocking embedding generation in threadpool with normalization and inference_mode
    def _encode_chunks():
        import torch
        with torch.inference_mode():
            return model.encode(
                chunks, batch_size=32, normalize_embeddings=True, show_progress_bar=False
            )

    embeddings = await run_in_threadpool(_encode_chunks)

    records = [
        {"meeting_id": meeting_id, "chunk_text": chunk, "embedding": emb.tolist()}
        for chunk, emb in zip(chunks, embeddings, strict=False)
    ]

    if records:
        try:
            def insert_chunks():
                # Batch inserts in chunks of 50 to avoid payload size limit issues
                batch_size = 50
                for start_idx in range(0, len(records), batch_size):
                    batch = records[start_idx : start_idx + batch_size]
                    supabase_client.table("meeting_chunks").insert(batch).execute()

            await run_in_threadpool(insert_chunks)
        except Exception as e:
            logger.warning(f"Failed to insert meeting chunks: {e}")


async def semantic_search(supabase_client, query: str, limit: int = 5):
    """
    Embeds the user's query and calls the Postgres RPC function to find similar chunks.
    Encodes query non-blockingly.
    """
    if not query or not query.strip():
        return []

    try:
        model = await run_in_threadpool(get_embedding_model)
        # Non-blocking query encoding with normalization and inference_mode
        def _encode_query():
            import torch
            with torch.inference_mode():
                return model.encode(
                    [query.strip()], normalize_embeddings=True, show_progress_bar=False
                )

        query_embeddings = await run_in_threadpool(_encode_query)
        query_vector = query_embeddings[0].tolist()

        def execute_rpc():
            return supabase_client.rpc(
                "match_meeting_chunks",
                {
                    "query_embedding": query_vector,
                    "match_threshold": 0.3,  # Cosine similarity threshold
                    "match_count": limit,
                },
            ).execute()

        response = await run_in_threadpool(execute_rpc)
        return response.data or []
    except Exception as e:
        logger.warning(f"Semantic search execution error: {e}")
        return []
