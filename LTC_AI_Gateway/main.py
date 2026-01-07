from __future__ import annotations

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes.analyze_item_photo import router as analyze_item_photo_router

# Load environment variables from .env as early as possible (process startup).
# This ensures ALL modules (Gemini, Google Places, etc.) see the same environment.
load_dotenv()

app = FastAPI(
    title="Legacy Treasure Chest AI Gateway",
    description="AI backend for item photo analysis and related tasks.",
    version="0.1.0",
)

# CORS – fine for iOS, we can tighten later if needed.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routes
app.include_router(analyze_item_photo_router)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}
