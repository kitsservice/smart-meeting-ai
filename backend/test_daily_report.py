"""
Offline Unit & Concept Test Suite for Daily Report & Short Summary Service
Validates duration parsing, attendee extraction, action item consolidation,
empty day handling, and markdown formatting without requiring network or external APIs.
"""

import sys
from pathlib import Path

# Add backend directory to sys.path
sys.path.insert(0, str(Path(__file__).parent))

from app.services.daily_report_service import daily_report_service


def test_concept_duration_parsing_and_formatting():
    """Concept 1: Duration parsing from string descriptions and human-readable formatting."""
    print("--- Concept 1: Testing Duration Extraction & Formatting ---")

    # HH:MM:SS format
    m1 = {"description": "Recorded for 01:15:30"}
    secs1 = daily_report_service.parse_meeting_duration(m1)
    assert secs1 == 4530, f"Expected 4530, got {secs1}"
    assert daily_report_service.format_duration_human(secs1) == "1 hr 15 mins"

    # MM:SS format
    m2 = {"description": "Recorded for 25:00"}
    secs2 = daily_report_service.parse_meeting_duration(m2)
    assert secs2 == 1500, f"Expected 1500, got {secs2}"
    assert daily_report_service.format_duration_human(secs2) == "25 mins"

    # X mins format
    m3 = {"description": "Recorded for 45 mins"}
    secs3 = daily_report_service.parse_meeting_duration(m3)
    assert secs3 == 2700, f"Expected 2700, got {secs3}"
    assert daily_report_service.format_duration_human(secs3) == "45 mins"

    # Direct duration field
    m4 = {"duration": 3600}
    secs4 = daily_report_service.parse_meeting_duration(m4)
    assert secs4 == 3600
    assert daily_report_service.format_duration_human(secs4) == "1 hr"

    print("[PASS] Duration parsing and human-readable formatting verified cleanly.")


def test_concept_attendee_extraction():
    """Concept 2: Real attendee name extraction avoiding generic placeholders."""
    print("--- Concept 2: Testing Real Attendee Extraction ---")

    meeting = {
        "description": (
            '[MEMBERS:[{"name":"Rohit Sharma","is_host":true},'
            '{"name":"Priya Verma","is_host":false},'
            '{"name":"Speaker 1","is_host":false}]]'
        ),
        "action_items": [
            {"task": "Prepare report", "assignee": "Rohit Sharma"},
            {"task": "Send email", "assignee": "Ananya Rao"},
            {"task": "Unassigned task", "assignee": "Guest 1"},
        ],
    }

    attendees = daily_report_service.extract_meeting_attendees(meeting)
    assert "Rohit Sharma" in attendees
    assert "Priya Verma" in attendees
    assert "Ananya Rao" in attendees
    assert "Speaker 1" not in attendees
    assert "Guest 1" not in attendees

    print(f"[PASS] Extracted verified attendees: {attendees}")


def test_concept_action_item_consolidation():
    """Concept 3: Grouping tasks by attendee name across multiple meetings."""
    print("--- Concept 3: Testing Action Item Consolidation by Assignee ---")

    meetings = [
        {
            "id": "m-101",
            "title": "Backend Sync",
            "action_items": [
                {
                    "id": "t-1",
                    "task": "Migrate database schema to v2",
                    "assignee": "Rohit Sharma",
                    "is_completed": False,
                },
                {
                    "id": "t-2",
                    "task": "Deploy staging server",
                    "assignee": "Vikram Malhotra",
                    "is_completed": True,
                },
            ],
        },
        {
            "id": "m-102",
            "title": "Frontend Sprint Planning",
            "action_items": [
                {
                    "id": "t-3",
                    "task": "Build Daily Report UI widget",
                    "assignee": "Rohit Sharma",
                    "is_completed": False,
                },
                {
                    "id": "t-4",
                    "task": "Prepare user onboarding slides",
                    "assignee": "Ananya Rao",
                    "is_completed": False,
                },
                {
                    "id": "t-5",
                    "task": "Send calendar invites",
                    "assignee": None,
                    "is_completed": False,
                },
            ],
        },
    ]

    all_items, grouped = daily_report_service.consolidate_action_items(meetings)

    assert len(all_items) == 5, f"Expected 5 items, got {len(all_items)}"
    assert "Rohit Sharma" in grouped, "Rohit Sharma missing in grouped items"
    assert len(grouped["Rohit Sharma"]) == 2, "Rohit Sharma should have 2 tasks"
    assert "Vikram Malhotra" in grouped, "Vikram Malhotra missing"
    assert len(grouped["Vikram Malhotra"]) == 1
    assert "Ananya Rao" in grouped, "Ananya Rao missing"
    assert "Unassigned" in grouped, "Unassigned missing for task with null assignee"
    assert grouped["Unassigned"][0]["task"] == "Send calendar invites"

    print("[PASS] Action items consolidated and grouped by proper attendee names.")


def test_concept_daily_report_generation_deterministic():
    """Concept 4: Full Daily Report & Short Summary generation across multiple meetings."""
    print("--- Concept 4: Testing Daily Report & Short Summary Synthesis ---")

    target_date = "2026-10-26"
    meetings = [
        {
            "id": "m-1",
            "title": "Quarterly Product Strategy",
            "description": (
                '[MEMBERS:[{"name":"Rohit Sharma","is_host":true},'
                '{"name":"Priya Verma","is_host":false}]] Recorded for 00:45:00'
            ),
            "summary": (
                "The team finalized the Q4 product roadmap. Decided to prioritize the "
                "Smart Meeting AI daily report and speaker diarization accuracy."
            ),
            "action_items": [
                {"task": "Ship daily report service", "assignee": "Rohit Sharma"}
            ],
            "created_at": f"{target_date}T10:00:00Z",
        },
        {
            "id": "m-2",
            "title": "Security & Infra Review",
            "description": (
                '[MEMBERS:[{"name":"Vikram Malhotra","is_host":true}]] Recorded for 00:30:00'
            ),
            "summary": (
                "Infra team reviewed cloud security credentials. Agreed to rotate all "
                "API keys by Friday."
            ),
            "action_items": [
                {"task": "Rotate API credentials", "assignee": "Vikram Malhotra"}
            ],
            "created_at": f"{target_date}T14:30:00Z",
        },
    ]

    report = daily_report_service.generate_daily_report_deterministic(meetings, target_date)

    assert report["status"] == "success"
    assert report["date"] == target_date
    assert report["total_meetings"] == 2
    assert report["total_duration_minutes"] == 75  # 45 + 30 mins
    assert report["total_duration_formatted"] == "1 hr 15 mins"
    assert "Rohit Sharma" in report["attendees"]
    assert "Priya Verma" in report["attendees"]
    assert "Vikram Malhotra" in report["attendees"]
    assert report["action_items_count"] == 2
    assert "Rohit Sharma" in report["action_items_by_assignee"]
    assert "Vikram Malhotra" in report["action_items_by_assignee"]
    assert len(report["short_summary"]) > 50

    print("[PASS] Daily Report & Short Summary synthesized successfully:")
    print(f"{report['short_summary']}")


def test_concept_empty_day_handling():
    """Concept 5: Graceful fallback when no meetings occurred on the requested date."""
    print("--- Concept 5: Testing Empty Day Handling ---")

    empty_report = daily_report_service.generate_daily_report_deterministic([], "2026-10-27")
    assert empty_report["status"] == "success"
    assert empty_report["total_meetings"] == 0
    assert empty_report["total_duration_minutes"] == 0
    assert empty_report["total_duration_formatted"] == "0 mins"
    assert empty_report["attendees"] == []
    assert empty_report["action_items_count"] == 0
    assert "No meetings were recorded" in empty_report["short_summary"]

    print("[PASS] Empty day handled gracefully without errors.")


def test_concept_markdown_presentation():
    """Concept 6: Markdown output generation with headers, metrics, and checkboxes."""
    print("--- Concept 6: Testing Markdown Presentation Generation ---")

    dummy_report = {
        "date": "2026-10-26",
        "total_meetings": 2,
        "total_duration_formatted": "1 hr 15 mins",
        "attendees": ["Rohit Sharma", "Vikram Malhotra"],
        "short_summary": "Successful sprint review and infra security hardening.",
        "key_decisions": ["Deploy to production on Friday", "Rotate cloud keys"],
        "action_items_by_assignee": {
            "Rohit Sharma": [
                {
                    "task": "Review PR #42",
                    "is_completed": True,
                    "meeting_title": "Sprint Review",
                }
            ],
            "Vikram Malhotra": [
                {
                    "task": "Run security audit",
                    "is_completed": False,
                    "meeting_title": "Infra Sync",
                }
            ],
        },
    }

    md = daily_report_service.format_daily_report_markdown(dummy_report)
    assert "# 📅 Executive Daily Report — 2026-10-26" in md
    assert "**Meetings Conducted:** 2" in md
    assert "## 🌟 Executive Short Summary" in md
    assert "- [x] Review PR #42" in md
    assert "- [ ] Run security audit" in md

    print("[PASS] Markdown representation formatted cleanly with headers and checkboxes.")


def run_all_daily_report_concept_tests():
    print("=========================================================")
    print("STARTING TEST CONCEPT SUITE: DAILY REPORT & SHORT SUMMARY")
    print("=========================================================\n")

    test_concept_duration_parsing_and_formatting()
    test_concept_attendee_extraction()
    test_concept_action_item_consolidation()
    test_concept_daily_report_generation_deterministic()
    test_concept_empty_day_handling()
    test_concept_markdown_presentation()

    print("\n=========================================================")
    print("ALL 6 TEST CONCEPTS PASSED WITH ZERO ERRORS!")
    print("=========================================================")


if __name__ == "__main__":
    run_all_daily_report_concept_tests()
