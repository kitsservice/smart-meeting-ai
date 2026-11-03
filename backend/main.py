import asyncio
import logging
from contextlib import asynccontextmanager

import os

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from starlette.concurrency import run_in_threadpool

from app.api.api import api_router
from app.core.config import settings
from app.services.deepgram_service import deepgram_service
from app.services.sarvam import sarvam_service

logger = logging.getLogger("uvicorn.info")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup actions: asynchronously pre-warm voice biometrics and vector embedding models
    # so first-time user calibration and similarity checks execute instantaneously without cold starts.
    async def _prewarm_models():
        try:
            from app.services.voice_biometrics import voice_biometrics
            _ = voice_biometrics.classifier
            logger.info("SpeechBrain Voice Biometrics model pre-warmed successfully.")
        except Exception as e:
            logger.warning("Voice biometrics model pre-warm skipped/failed: %s", e)

        try:
            from app.services.vector_search import get_embedding_model
            _ = get_embedding_model()
            logger.info("SentenceTransformer embedding model pre-warmed successfully.")
        except Exception as e:
            logger.warning("Vector search model pre-warm skipped/failed: %s", e)

    asyncio.create_task(run_in_threadpool(_prewarm_models))
    yield
    # Shutdown actions: gracefully close HTTP sessions
    await deepgram_service.aclose()
    await sarvam_service.aclose()


app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Backend API for Smart Meeting AI connecting to Supabase and Sarvam AI.",
    version="1.0.0",
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    lifespan=lifespan,
)

# Enable GZip compression for large transcripts and payloads
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Enable CORS for Flutter mobile, desktop, and web communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.API_V1_STR)


@app.get("/")
def root():
    return {
        "message": "Welcome to Smart Meeting AI Backend",
        "docs": "/docs",
        "status": "healthy",
    }


@app.get("/health")
def health():
    return {
        "status": "healthy",
        "version": "2.0.3",
        "supabase_configured": bool(settings.SUPABASE_URL and settings.SUPABASE_KEY),
    }


@app.get("/privacy", response_class=HTMLResponse)
@app.get("/privacy-policy", response_class=HTMLResponse)
def privacy_page():
    privacy_file = os.path.join(os.path.dirname(__file__), "privacy.html")
    if os.path.exists(privacy_file):
        return FileResponse(privacy_file, media_type="text/html")
    # Fallback to parent docs if running from root
    parent_docs = os.path.join(os.path.dirname(os.path.dirname(__file__)), "docs", "index.html")
    if os.path.exists(parent_docs):
        return FileResponse(parent_docs, media_type="text/html")
    return HTMLResponse("<h1>Smart Meeting AI Privacy Policy</h1><p>Contact: kitsserviceakola@gmail.com</p>")



if __name__ == "__main__":
    import os

    port = int(os.environ.get("PORT", "8000"))
    is_reload = os.environ.get("ENV", "development").lower() == "development"
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=is_reload)
