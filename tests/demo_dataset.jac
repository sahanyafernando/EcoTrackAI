"""Offline synthetic fixture tests; expected membership exists only in tests."""
import os;
import secrets;
import tempfile;
import from datetime { datetime, timezone, timedelta }
import from jaclang.testing.testing { JacTestClient }
import from core.demo_dataset { DEMO_DATASET, demo_enabled, synthetic_observations }
import from contracts.report_views { ReportView }
import from core.intelligence { IntelligenceConfig, find_candidate_reports, candidate_signal, calculate_report_distance }

def rpc(client: JacTestClient, name: str, body: dict[str, any] = {}) -> any {
    response = client.post("/function/" + name, json=body);
    assert response.ok, response.text;
    return response.json()["data"]["result"];
}

def real_draft(near_demo: bool = False) -> dict[str, any] {
    return {"description": "Discarded sacks and plastic bags on the canal bank beside the Nelum Lane footbridge" if near_demo else "Citizen observed a damaged public bench",
        "category": "illegal_dumping" if near_demo else "damaged_public_space",
        "latitude": 6.9272 if near_demo else 7.5, "longitude": 79.8612 if near_demo else 80.3,
        "location_text": "Nelum Lane canal footbridge" if near_demo else "",
        "submission_id": secrets.token_urlsafe(24)};
}

def public_data(value: any) -> any {
    if isinstance(value, dict) { return {key: public_data(item) for (key, item) in value.items() if not key.startswith("_jac_")}; }
    if isinstance(value, list) { return [public_data(item) for item in value]; }
    return value;
}

obj DemoEnvironment {
    has enabled: str | None = None, authority: str | None = None;
    def __enter__() -> DemoEnvironment {
        self.enabled = os.environ.get("ECOTRACK_ENABLE_DEMO_SEED");
        self.authority = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS");
        os.environ["ECOTRACK_ENABLE_DEMO_SEED"] = "true";
        os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = "";
        return self;
    }
    def __exit__(kind: any, value: any, trace: any) -> None {
        for (name, previous) in [("ECOTRACK_ENABLE_DEMO_SEED", self.enabled), ("ECOTRACK_AUTHORITY_ROOT_IDS", self.authority)] {
            if previous is None { os.environ.pop(name, None); }
            else { os.environ[name] = previous; }
        }
    }
}

def authority(client: JacTestClient, name: str = "authority") -> str {
    assert client.register_user(name, secrets.token_urlsafe(24)).ok;
    id = rpc(client, "account")["root_id"];
    current = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS", "");
    os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = current + "," + id;
    return client._auth_token or "";
}
