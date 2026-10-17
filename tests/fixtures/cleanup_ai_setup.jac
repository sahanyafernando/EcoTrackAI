"""Native cleanup integration helpers; fixture LLMs are offline only."""
import os;
import secrets;
import tempfile;
import from datetime { datetime, timezone, timedelta }
import from jaclang.testing.testing { JacTestClient }

def rpc(client: JacTestClient, name: str, body: dict[str, any] = {}) -> any {
    result = client.post("/function/" + name, json=body);
    assert result.ok, result.text;
    return result.json()["data"]["result"];
}
obj AuthorityEnvironment {
    has previous: str | None = None;
    def __enter__() -> AuthorityEnvironment {
        self.previous = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS");
        os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = "";
        return self;
    }
    def __exit__(kind: any, value: any, trace: any) -> None {
        if self.previous is None { os.environ.pop("ECOTRACK_AUTHORITY_ROOT_IDS", None); }
        else { os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = self.previous; }
    }
}
def prepare(client: JacTestClient, password: str, assign_responses: bool = True) -> dict[str, any] {
    assert client.register_user("citizen_a", password).ok;
    citizen = client._auth_token or "";
    for latitude in [6.9271, 6.9274] {
        rpc(client, "create_report", {"description": "Waste beside canal bridge", "category": "illegal_dumping",
            "latitude": latitude, "longitude": 79.8612, "location_text": "Canal bridge", "submission_id": secrets.token_urlsafe(24)});
    }
    assert client.register_user("citizen_b", password).ok;
    second = client._auth_token or "";
    assert client.register_user("authority", password).ok;
    os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = rpc(client, "account")["root_id"];
    authority = client._auth_token or "";
    rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24)});
    proposal = rpc(client, "incident_intelligence_state")["proposals"][0];
    incident = rpc(client, "review_cluster", {"proposal_id": proposal["proposal_id"], "decision": "confirmed", "expected_revision": 1})["incident_id"];
    tokens: dict[str, str] = {}; ids: dict[str, str] = {}; usernames: dict[str, str] = {};
    for state in ["verified_a", "verified_b", "pending", "suspended"] {
        assert client.register_user(state, password).ok;
        org = rpc(client, "apply", {"name": state + " Environment", "description": "Community canal waste response"});
        tokens[state] = client._auth_token or ""; ids[state] = org["id"]; usernames[org["id"]] = state;
        client.set_auth_token(authority);
        if state != "pending" {
            rpc(client, "review", {"organization_id": org["id"], "decision": "verified", "expected_revision": 1});
            if state == "suspended" { rpc(client, "review", {"organization_id": org["id"], "decision": "suspended", "expected_revision": 2}); }
        }
    }
    if not assign_responses {
        return {"incident": incident, "authority": authority, "citizen": citizen, "second": second,
            "lead": tokens["verified_a"], "lead_id": ids["verified_a"], "support": tokens["verified_b"],
            "pending": tokens["pending"], "suspended": tokens["suspended"]};
    }
    run = rpc(client, "fixture_coordination", {"incident_id": incident, "request_id": secrets.token_urlsafe(24)});
    rec = rpc(client, "incident_response_board")["incidents"][0]["recommendations"][0];
    lead = rec["lead_organization_id"]; support = rec["support_organization_ids"][0];
    for (id, role) in [(lead, "lead"), (support, "support")] {
        revision = rpc(client, "incident_response_board")["incidents"][0]["revision"];
        rpc(client, "accept_response", {"incident_id": incident, "organization_id": id, "role": role, "expected_revision": revision, "run_id": run["id"]});
    }
    return {"incident": incident, "authority": authority, "citizen": citizen, "second": second,
        "lead": tokens[usernames[lead]], "lead_name": usernames[lead], "lead_id": lead,
        "support": tokens[usernames[support]], "pending": tokens["pending"], "suspended": tokens["suspended"]};
}
def draft(incident: str) -> dict[str, any] {
    return {"incident_id": incident, "title": "Canal bank cleanup", "description": "Collect loose litter with the Lead group.",
        "location_text": "Meet beside the canal bridge", "latitude": 6.9271, "longitude": 79.8612,
        "scheduled_at": (datetime.now(timezone.utc) + timedelta(days=2)).isoformat(), "required_volunteers": 8};
}
def create(client: JacTestClient, setup: dict[str, any]) -> any {
    client.set_auth_token(setup["lead"]);
    return rpc(client, "create_cleanup_event", draft(setup["incident"]));
}
