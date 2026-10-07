# E:\Ares-Smart meeting\backend\app\services\vector_search.py
import re
from typing import List

# We will load the model lazily so it doesn't slow down backend startup
_embedding_model = None

def get_embedding_model():
    global _embedding_model
    if _embedding_model is None:
        try:
            from sentence_transformers import SentenceTransformer
            # all-MiniLM-L6-v2 produces 384-dimensional vectors. Extremely fast and lightweight.
            _embedding_model = SentenceTransformer('all-MiniLM-L6-v2')
        except ImportError:
            raise Exception("sentence-transformers is not installed. Run: pip install sentence-transformers")
    return _embedding_model

def chunk_text(text: str, chunk_size: int = 500, overlap: int = 50) -> List[str]:
    """
    Splits a long transcript into overlapping chunks to ensure context is preserved.
    """
    words = text.split()
    chunks = []
    i = 0
    while i < len(words):
        chunk = " ".join(words[i:i + chunk_size])
        chunks.append(chunk)
        i += (chunk_size - overlap)
    return chunks

async def process_and_store_transcript(supabase_client, meeting_id: str, transcript: str):
    """
    Chunks a transcript, generates embeddings, and saves them to Supabase.
    """
    if not transcript or len(transcript.strip()) < 10:
        return
        
    model = get_embedding_model()
    chunks = chunk_text(transcript)
    
    # Generate vectors for all chunks
    # model.encode returns a numpy array, we convert to list of floats for pgvector
    embeddings = model.encode(chunks)
    
    records = []
    for chunk, emb in zip(chunks, embeddings):
        records.append({
            "meeting_id": meeting_id,
            "chunk_text": chunk,
            "embedding": emb.tolist()
        })
        
    if records:
        # Bulk insert into Supabase
        # Make sure RLS policies allow this, or use service_role key
        supabase_client.table("meeting_chunks").insert(records).execute()

async def semantic_search(supabase_client, query: str, limit: int = 5):
    """
    Embeds the user's query and calls the Postgres RPC function to find similar chunks.
    """
    model = get_embedding_model()
    query_vector = model.encode([query])[0].tolist()
    
    response = supabase_client.rpc(
        "match_meeting_chunks", 
        {
            "query_embedding": query_vector,
            "match_threshold": 0.3, # Cosine similarity threshold
            "match_count": limit
        }
    ).execute()
    
    return response.data
