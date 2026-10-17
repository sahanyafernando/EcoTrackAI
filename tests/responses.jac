"""Offline Task 5 integration helpers. No imports of peer test annexes."""
import os;
import secrets;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

def rpc(client: JacTestClient, name: str, body: dict[str, any] = {}) -> any {
    result = client.post("/function/" + name, json=body);
    assert result.ok, result.text;
    return result.json()["data"]["result"];
}
def public_data(value: any) -> any {
    if isinstance(value, dict) { return {key: public_data(item) for (key, item) in value.items() if not key.startswith("_jac_")}; }
    if isinstance(value, list) { return [public_data(item) for item in value]; }
    return value;
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
def prepare(client: JacTestClient, organizations: bool = True) -> dict[str, any] {
    assert client.register_user("citizen", secrets.token_urlsafe(24)).ok;
    citizen_token = client._auth_token or "";
    for latitude in [6.9271, 6.9274] {
        rpc(client, "create_report", {"description": "Waste beside canal bridge", "category": "illegal_dumping",
            "latitude": latitude, "longitude": 79.8612, "location_text": "Canal bridge",
            "submission_id": secrets.token_urlsafe(24)});
    }
    password = secrets.token_urlsafe(24);
    assert client.register_user("authority", password).ok;
    os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = rpc(client, "account")["root_id"];
    authority = client._auth_token or "";
    rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24)});
    proposal = rpc(client, "incident_intelligence_state")["proposals"][0];
    incident = rpc(client, "review_cluster", {"proposal_id": proposal["proposal_id"], "decision": "confirmed", "expected_revision": 1})["incident_id"];
    orgs: dict[str, str] = {}; tokens: dict[str, str] = {};
    if organizations {
        for state in ["first", "second", "third", "pending", "suspended", "rejected"] {
            assert client.register_user(state, secrets.token_urlsafe(24)).ok;
            org = rpc(client, "apply", {"name": state + " Environmental Group", "description": "Canal waste and community environmental response"});
            orgs[state] = org["id"]; tokens[state] = client._auth_token or "";
            client.set_auth_token(authority);
            if state != "pending" {
                rpc(client, "review", {"organization_id": org["id"], "decision": "rejected" if state == "rejected" else "verified", "expected_revision": 1});
                if state == "suspended" { rpc(client, "review", {"organization_id": org["id"], "decision": "suspended", "expected_revision": 2}); }
            }
        }
    }
    return {"incident": incident, "authority": authority, "password": password,
        "citizen": citizen_token, "orgs": orgs, "tokens": tokens};
}
def coordinate(client: JacTestClient, incident: str, mode: str = "positive") -> any {
    return rpc(client, "fixture_coordination", {"incident_id": incident, "request_id": secrets.token_urlsafe(24), "mode": mode});
}
def assignment(client: JacTestClient, incident: str, org: str, role: str, run: str) -> dict[str, any] {
    current = rpc(client, "incident_response_board")["incidents"][0];
    return {"incident_id": incident, "organization_id": org, "role": role,
        "expected_revision": current["revision"], "run_id": run};
}
