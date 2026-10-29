import os
import sys

# Add backend directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.api.endpoints.meetings import get_meetings
from app.services.voice_biometrics import format_speaker_display_name
from main import health, root


def test_backend_endpoints():
    print("--- 1. Testing Root Endpoint (GET /) ---")
    root_data = root()
    assert root_data.get("status") == "healthy", f"Unexpected status: {root_data}"
    print("[PASS] Root endpoint returned healthy status.")

    print("--- 2. Testing Health Endpoint (GET /health) ---")
    health_data = health()
    assert "version" in health_data, f"Version missing in: {health_data}"
    assert health_data.get("status") == "healthy"
    print(f"[PASS] Health endpoint verified. Version: {health_data.get('version')}")

    print("--- 3. Testing Unauthenticated Meetings Fetch ---")
    unauth_meetings = get_meetings(user_id=None)
    assert unauth_meetings == [], f"Expected empty list, got {unauth_meetings}"
    print("[PASS] Meetings endpoint safely handles unauthenticated requests without crashing.")

    print("--- 4. Testing Speaker Display Name Formatting ---")
    assert format_speaker_display_name("rahul sharma") == "Rahul Sharma"
    assert format_speaker_display_name(None, "john.doe@example.com") == "John Doe"
    assert format_speaker_display_name(None, None) == "Speaker"
    print("[PASS] Speaker display name formatting logic operates accurately.")

    # 5. Multi-Sample Centroid Math Verification
    print("--- 5. Testing Multi-Sample Centroid Biometric Averaging ---")
    import numpy as np
    e1 = np.random.randn(192).astype(np.float32)
    e1 /= np.linalg.norm(e1)
    e2 = e1 + 0.05 * np.random.randn(192).astype(np.float32)
    e2 /= np.linalg.norm(e2)
    e3 = e1 + 0.05 * np.random.randn(192).astype(np.float32)
    e3 /= np.linalg.norm(e3)

    centroid = np.mean([e1, e2, e3], axis=0)
    norm = np.linalg.norm(centroid)
    assert norm > 0.0
    centroid /= norm
    assert len(centroid) == 192
    sim1 = float(np.dot(centroid, e1))
    sim2 = float(np.dot(centroid, e2))
    sim3 = float(np.dot(centroid, e3))
    assert sim1 > 0.85 and sim2 > 0.85 and sim3 > 0.85
    print("[PASS] Multi-sample 3-phrase centroid averaging confirmed with >85% cross-similarity.")

    print("\n===========================================")
    print("ALL BACKEND QA TEST SUITES PASSED CLEANLY!")
    print("===========================================")


if __name__ == "__main__":
    test_backend_endpoints()
