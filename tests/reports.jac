"""Report validation and native endpoint test fixtures."""
import os;
import secrets;
import tempfile;
import from math { nan, inf }
import from concurrent.futures { ThreadPoolExecutor }
import from jaclang.testing.testing { JacTestClient }
import from jaclang.testing.test { parametrize }
import from core.reports { validate_report, REPORT_CATEGORIES }

def rpc(client: JacTestClient, name: str, body: dict[str, any] = {}) -> any {
    response = client.post("/function/" + name, json=body);
    assert response.ok, response.text;
    return response.json()["data"]["result"];
}

def draft() -> dict[str, any] {
    return {"description": "Waste beside the canal", "category": "illegal_dumping",
            "latitude": 6.9271, "longitude": 79.8612, "location_text": "Beside the bridge",
            "submission_id": secrets.token_urlsafe(24)};
}

def _invalid_report(values: tuple[str, str, float, float, str, str]) {
    with testraises(ValueError) {
        validate_report(values[0], values[1], values[2], values[3], values[4], values[5]);
    }
}

with entry {
    parametrize("invalid report validation", [
        (" ", "other", 0.0, 0.0, "", "valid-request-key"),
        ("x" * 5001, "other", 0.0, 0.0, "", "valid-request-key"),
        ("Observed", "invented", 0.0, 0.0, "", "valid-request-key"),
        ("Observed", "other", 90.01, 0.0, "", "valid-request-key"),
        ("Observed", "other", -90.01, 0.0, "", "valid-request-key"),
        ("Observed", "other", 0.0, 180.01, "", "valid-request-key"),
        ("Observed", "other", 0.0, -180.01, "", "valid-request-key"),
        ("Observed", "other", nan, 0.0, "", "valid-request-key"),
        ("Observed", "other", 0.0, inf, "", "valid-request-key"),
        ("Observed", "other", 0.0, 0.0, "x" * 501, "valid-request-key"),
        ("Observed", "other", 0.0, 0.0, "", "short")
    ], _invalid_report);
}
