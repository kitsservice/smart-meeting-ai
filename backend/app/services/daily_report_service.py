import json
import logging
import re
from typing import Any

from app.core.config import settings
from app.services.speaker_resolver import parse_members_from_description

logger = logging.getLogger(__name__)

# Precompiled regular expressions for high-performance meeting metadata extraction
RE_RECORDED_FOR_HMS = re.compile(r"Recorded for (?:(\d+):)?(\d+):(\d+)")
RE_RECORDED_FOR_UNIT = re.compile(r"Recorded for (\d+)\s*(min|m|sec|s)", re.IGNORECASE)
RE_NON_HUMAN_NAME = re.compile(r"^(speaker|guest)\s*\d*$", re.IGNORECASE)
NON_HUMAN_EXACT = frozenset({"speaker", "guest", "unassigned", "null", "none", "unknown", ""})


class DailyReportService:
    """Service to aggregate, synthesize, and generate executive daily reports

    and short summaries across all meetings recorded on a specific date.
    """

    def __init__(self):
        self._gemini_client = None

    def _get_gemini_client(self):
        if self._gemini_client is None and settings.GEMINI_API_KEY:
            try:
                from google import genai

                self._gemini_client = genai.Client(api_key=settings.GEMINI_API_KEY)
            except Exception as e:
                logger.warning(f"Failed to initialize Gemini client for DailyReport: {e}")
        return self._gemini_client

    def parse_meeting_duration(self, meeting: dict[str, Any]) -> int:
        """Extracts meeting duration in seconds from duration field or description string."""
        dur = meeting.get("duration")
        if isinstance(dur, (int, float)) and dur > 0:
            return round(dur)

        desc = str(meeting.get("description") or "")
        # Pattern 1: Recorded for HH:MM:SS or MM:SS
        m = RE_RECORDED_FOR_HMS.search(desc)
        if m:
            hours = int(m.group(1)) if m.group(1) else 0
            mins = int(m.group(2))
            secs = int(m.group(3))
            return hours * 3600 + mins * 60 + secs

        # Pattern 2: Recorded for X mins / X min / X s
        m2 = RE_RECORDED_FOR_UNIT.search(desc)
        if m2:
            val = int(m2.group(1))
            unit = m2.group(2).lower()
            return val * 60 if "m" in unit else val

        # Estimate from transcript word count if available (~130 words per minute)
        transcript = str(meeting.get("transcript") or "")
        word_count = len(transcript.split())
        if word_count > 20:
            est_minutes = max(1, round(word_count / 130))
            return est_minutes * 60

        return 300  # Default 5 minutes fallback

    def format_duration_human(self, seconds: int) -> str:
        """Formats seconds into human-readable duration like '1 hr 15 mins' or '25 mins'."""
        if seconds <= 0:
            return "0 mins"
        hours = seconds // 3600
        remainder_secs = seconds % 3600
        mins = remainder_secs // 60

        if hours > 0:
            if mins > 0:
                return f"{hours} hr {mins} min" if mins == 1 else f"{hours} hr {mins} mins"
            return f"{hours} hr"
        if mins > 0:
            return f"{mins} min" if mins == 1 else f"{mins} mins"
        return f"{seconds} secs"

    @staticmethod
    def is_meaningful_human_name(name: str | None) -> bool:
        """Determines if a name is a genuine person name rather than a placeholder."""
        if not name or not isinstance(name, str):
            return False
        clean = name.strip()
        lower = clean.lower()
        if lower in NON_HUMAN_EXACT:
            return False
        if RE_NON_HUMAN_NAME.match(lower):
            return False
        return True

    def extract_meeting_attendees(self, meeting: dict[str, Any]) -> list[str]:
        """Extracts unique human names of attendees from description tags and action items."""
        attendee_names: set[str] = set()
        desc = str(meeting.get("description") or "")
        members = parse_members_from_description(desc)
        for mem in members:
            name = mem.get("name")
            if self.is_meaningful_human_name(name):
                attendee_names.add(str(name).strip())

        # Also inspect action item assignees
        action_items = meeting.get("action_items") or []
        if isinstance(action_items, list):
            for item in action_items:
                if isinstance(item, dict):
                    assignee = item.get("assignee")
                    if self.is_meaningful_human_name(assignee):
                        attendee_names.add(str(assignee).strip())

        return sorted(list(attendee_names))

    def consolidate_action_items(
        self, meetings: list[dict[str, Any]]
    ) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]]]:
        """Aggregates all action items across the day's meetings and groups them by attendee."""
        all_items: list[dict[str, Any]] = []
        grouped_by_assignee: dict[str, list[dict[str, Any]]] = {}

        for meeting in meetings:
            m_title = meeting.get("title", "Meeting")
            items = meeting.get("action_items") or []
            if not isinstance(items, list):
                continue

            for raw in items:
                if isinstance(raw, str):
                    task_text = raw.strip()
                    assignee = None
                    is_done = False
                    item_id = None
                elif isinstance(raw, dict):
                    task_text = str(raw.get("task") or raw.get("text") or "").strip()
                    assignee = raw.get("assignee")
                    is_done = bool(raw.get("is_completed", False))
                    item_id = raw.get("id")
                else:
                    continue

                if not task_text:
                    continue

                assignee_display = (
                    str(assignee).strip()
                    if self.is_meaningful_human_name(assignee)
                    else "Unassigned"
                )

                item_obj = {
                    "id": item_id,
                    "task": task_text,
                    "assignee": assignee_display,
                    "is_completed": is_done,
                    "meeting_title": m_title,
                    "meeting_id": meeting.get("id"),
                }
                all_items.append(item_obj)

                if assignee_display not in grouped_by_assignee:
                    grouped_by_assignee[assignee_display] = []
                grouped_by_assignee[assignee_display].append(item_obj)

        return all_items, grouped_by_assignee

    def _synthesize_extractive_fallback(
        self,
        meetings: list[dict[str, Any]],
        target_date: str,
        total_duration_str: str,
        attendees: list[str],
        action_items: list[dict[str, Any]],
    ) -> dict[str, Any]:
        """Fast, robust extractive daily report fallback without external API dependencies."""
        attendees_str = ", ".join(attendees) if attendees else "the team"
        titles_str = ", ".join([f"'{m.get('title', 'Meeting')}'" for m in meetings[:3]])

        # Merge key points from individual summaries
        summary_snippets = []
        for m in meetings:
            s = (m.get("summary") or "").strip()
            if s:
                first_sentence = s.split(".")[0].strip()
                if first_sentence:
                    summary_snippets.append(f"{m.get('title')}: {first_sentence}.")

        combined_snippets = (
            " ".join(summary_snippets[:3])
            if summary_snippets
            else f"Discussions covered key agenda items across {titles_str}."
        )

        short_summary = (
            f"On {target_date}, {len(meetings)} meeting(s) took place spanning "
            f"{total_duration_str} involving {attendees_str}. {combined_snippets} "
            f"A total of {len(action_items)} action item(s) were captured for follow-up."
        )

        # Extract plausible decisions from summaries or title
        decisions: list[str] = []
        decision_keywords = ["decided", "agreed", "approved", "finalized", "chosen"]
        for m in meetings:
            s = (m.get("summary") or "").strip()
            for line in s.split("\n"):
                lower = line.lower()
                if any(k in lower for k in decision_keywords):
                    clean_line = line.strip(" -*#•\t")
                    if clean_line and len(clean_line) > 10:
                        decisions.append(clean_line)

        if not decisions:
            decisions = [
                f"Completed discussions and established next steps for {m.get('title')}"
                for m in meetings[:3]
            ]

        topics = [m.get("title", "Project Review") for m in meetings]

        return {
            "short_summary": short_summary,
            "key_decisions": decisions[:5],
            "topics_covered": topics[:6],
        }

    async def _synthesize_with_gemini(
        self,
        meetings: list[dict[str, Any]],
        target_date: str,
        total_duration_str: str,
        attendees: list[str],
        action_items: list[dict[str, Any]],
    ) -> dict[str, Any] | None:
        """Synthesizes high-level executive short summary and key decisions using Gemini."""
        client = self._get_gemini_client()
        if client is None:
            return None

        from google.genai import types

        meeting_summaries_text = []
        for i, m in enumerate(meetings, start=1):
            title = m.get("title", f"Meeting {i}")
            summary = m.get("summary", "No summary available")
            meeting_summaries_text.append(f"Meeting {i}: {title}\nSummary: {summary}")

        meetings_context = "\n\n".join(meeting_summaries_text)
        action_items_text = "\n".join(
            [f"- {it.get('task')} (Assignee: {it.get('assignee')})" for it in action_items[:15]]
        ) or "None captured"

        prompt = f"""You are an executive Chief of Staff and strategic meeting analyst.
Analyze all meetings on {target_date} and synthesize a consolidated daily executive report.

MEETINGS CONDUCTED TODAY ({len(meetings)} meeting(s), Total duration: {total_duration_str}):
{meetings_context}

ACTION ITEMS CAPTURED:
{action_items_text}

ATTENDEES INVOLVED:
{", ".join(attendees) if attendees else "Team members"}

Respond strictly with a JSON object in this format (no markdown fences):
{{
    "short_summary": "A cohesive overview synthesizing the entire day's progress.",
    "key_decisions": [
        "Major decision 1 agreed upon today",
        "Major decision 2 approved today"
    ],
    "topics_covered": [
        "Topic 1",
        "Topic 2"
    ]
}}
"""
        for model_name in ["gemini-2.5-flash", "gemini-3.8-flash"]:
            try:
                response = client.models.generate_content(
                    model=model_name,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                    ),
                )
                raw = (response.text or "").strip()
                if raw.startswith("```json"):
                    raw = raw[7:]
                elif raw.startswith("```"):
                    raw = raw[3:]
                if raw.endswith("```"):
                    raw = raw[:-3]
                parsed = json.loads(raw.strip())
                if isinstance(parsed, dict) and parsed.get("short_summary"):
                    return parsed
            except Exception as e:
                logger.warning(f"Gemini Daily Report error with {model_name}: {e}")

        return None

    def generate_daily_report_deterministic(
        self, meetings: list[dict[str, Any]], target_date: str
    ) -> dict[str, Any]:
        """Synchronous deterministic generator used for instant local rendering and unit testing."""
        if not meetings:
            return {
                "status": "success",
                "date": target_date,
                "total_meetings": 0,
                "total_duration_minutes": 0,
                "total_duration_formatted": "0 mins",
                "attendees": [],
                "short_summary": f"No meetings were recorded on {target_date}.",
                "key_decisions": [],
                "topics_covered": [],
                "action_items_count": 0,
                "action_items_by_assignee": {},
                "all_action_items": [],
                "meetings": [],
            }

        total_secs = sum(self.parse_meeting_duration(m) for m in meetings)
        total_duration_formatted = self.format_duration_human(total_secs)
        total_duration_minutes = round(total_secs / 60)

        attendee_set = set()
        for m in meetings:
            for name in self.extract_meeting_attendees(m):
                attendee_set.add(name)
        attendees = sorted(list(attendee_set))

        all_action_items, grouped_action_items = self.consolidate_action_items(meetings)

        synthesis = self._synthesize_extractive_fallback(
            meetings=meetings,
            target_date=target_date,
            total_duration_str=total_duration_formatted,
            attendees=attendees,
            action_items=all_action_items,
        )

        return {
            "status": "success",
            "date": target_date,
            "total_meetings": len(meetings),
            "total_duration_minutes": total_duration_minutes,
            "total_duration_formatted": total_duration_formatted,
            "attendees": attendees,
            "short_summary": synthesis["short_summary"],
            "key_decisions": synthesis["key_decisions"],
            "topics_covered": synthesis["topics_covered"],
            "action_items_count": len(all_action_items),
            "action_items_by_assignee": grouped_action_items,
            "all_action_items": all_action_items,
            "meetings": [
                {
                    "id": m.get("id"),
                    "title": m.get("title"),
                    "duration_seconds": self.parse_meeting_duration(m),
                    "summary": m.get("summary"),
                    "created_at": m.get("created_at"),
                }
                for m in meetings
            ],
        }

    async def generate_daily_report(
        self, meetings: list[dict[str, Any]], target_date: str
    ) -> dict[str, Any]:
        """Main entry point: Generates high-level executive report synthesizing daily meetings."""
        if not meetings:
            return self.generate_daily_report_deterministic(meetings, target_date)

        report = self.generate_daily_report_deterministic(meetings, target_date)

        # Attempt Gemini high-level synthesis if configured
        if settings.GEMINI_API_KEY:
            ai_synthesis = await self._synthesize_with_gemini(
                meetings=meetings,
                target_date=target_date,
                total_duration_str=report["total_duration_formatted"],
                attendees=report["attendees"],
                action_items=report["all_action_items"],
            )
            if ai_synthesis:
                report["short_summary"] = (
                    ai_synthesis.get("short_summary") or report["short_summary"]
                )
                report["key_decisions"] = (
                    ai_synthesis.get("key_decisions") or report["key_decisions"]
                )
                report["topics_covered"] = (
                    ai_synthesis.get("topics_covered") or report["topics_covered"]
                )

        return report

    def format_daily_report_markdown(self, report: dict[str, Any]) -> str:
        """Renders the executive daily report as structured markdown for chat UI or export."""
        date = report.get("date", "")
        count = report.get("total_meetings", 0)
        dur = report.get("total_duration_formatted", "0 mins")
        attendees = report.get("attendees", [])
        short_summary = report.get("short_summary", "")
        decisions = report.get("key_decisions", [])
        grouped_items = report.get("action_items_by_assignee", {})

        md = [
            f"# 📅 Executive Daily Report — {date}",
            f"**Meetings Conducted:** {count} | **Total Time:** {dur}",
        ]
        if attendees:
            md.append(f"**Participants:** {', '.join(attendees)}")

        md.append("\n## 🌟 Executive Short Summary")
        md.append(short_summary)

        if decisions:
            md.append("\n## 🎯 Key Decisions Made")
            for d in decisions:
                md.append(f"- {d}")

        if grouped_items:
            md.append("\n## 📋 Action Items by Assignee")
            for assignee, items in grouped_items.items():
                md.append(f"### 👤 {assignee}")
                for it in items:
                    box = "[x]" if it.get("is_completed") else "[ ]"
                    meeting_tag = (
                        f" _({it.get('meeting_title')})_" if it.get("meeting_title") else ""
                    )
                    md.append(f"- {box} {it.get('task')}{meeting_tag}")
        else:
            md.append("\n## 📋 Action Items")
            md.append("_No action items captured today._")

        return "\n".join(md)


daily_report_service = DailyReportService()
