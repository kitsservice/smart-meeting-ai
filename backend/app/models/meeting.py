from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel

class ActionItem(BaseModel):
    id: str
    task: str
    assignee: Optional[str] = None
    is_completed: bool = False

class MeetingBase(BaseModel):
    title: str
    description: Optional[str] = None
    user_id: Optional[str] = None

class MeetingCreate(MeetingBase):
    pass

class Meeting(MeetingBase):
    id: str
    created_at: datetime
    transcript: Optional[str] = None
    summary: Optional[str] = None
    action_items: Optional[List[ActionItem]] = []

    class Config:
        from_attributes = True
