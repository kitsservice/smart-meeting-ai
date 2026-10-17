from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.api import api_router
from app.core.config import settings
from app.services.deepgram_service import deepgram_service
from app.services.sarvam import sarvam_service


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup actions
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
        "version": "2.0.1",
        "supabase_configured": bool(settings.SUPABASE_URL and settings.SUPABASE_KEY),
    }



if __name__ == "__main__":
    import os

    port = int(os.environ.get("PORT", "8000"))
    is_reload = os.environ.get("ENV", "development").lower() == "development"
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=is_reload)
