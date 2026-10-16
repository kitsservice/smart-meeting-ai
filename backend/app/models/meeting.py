import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field, field_validator


class ActionItem(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    task: str
    assignee: str | None = None
    is_completed: bool = False


class MeetingBase(BaseModel):
    title: str
    description: str | None = None
    user_id: str | None = None


class MeetingCreate(MeetingBase):
    pass


class Meeting(MeetingBase):
    id: str
    created_at: datetime
    transcript: str | None = None
    summary: str | None = None
    action_items: list[ActionItem] = Field(default_factory=list)

    @field_validator("action_items", mode="before")
    @classmethod
    def sanitize_action_items(cls, v: Any) -> list[dict]:
        if v is None:
            return []
        if isinstance(v, list):
            sanitized = []
            for item in v:
                if isinstance(item, str):
                    sanitized.append(
                        {
                            "id": str(uuid.uuid4()),
                            "task": item,
                            "assignee": None,
                            "is_completed": False,
                        }
                    )
                elif isinstance(item, dict):
                    task_text = item.get("task") or item.get("text") or item.get("title") or ""
                    sanitized.append(
                        {
                            "id": str(item.get("id") or uuid.uuid4()),
                            "task": str(task_text),
                            "assignee": item.get("assignee"),
                            "is_completed": bool(item.get("is_completed", False)),
                        }
                    )
                elif isinstance(item, ActionItem):
                    sanitized.append(item.model_dump())
            return sanitized
        return []

    class Config:
        from_attributes = True
