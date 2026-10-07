from fastapi import APIRouter
from app.api.endpoints import meetings
from app.api.endpoints import users

api_router = APIRouter()
api_router.include_router(meetings.router, prefix="/meetings", tags=["meetings"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
