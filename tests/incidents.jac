"""Task 4 offline native-auth/graph integration tests, using the real proposal pipeline."""
import os;
import secrets;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

# Keep this suite independent: importing another .test annex also collects its tests.
def rpc(client: JacTestClient, name: str, body: dict[str, any] = {}) -> any {
    response = client.post("/function/" + name, json=body);
    assert response.ok, response.text;
    return response.json()["data"]["result"];
}
def draft() -> dict[str, any] {
    return {"description": "Waste beside the canal bridge", "category": "illegal_dumping",
        "latitude": 6.9271, "longitude": 79.8612, "location_text": "Beside the bridge",
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
def authority(client: JacTestClient, name: str = "authority") -> None {
    assert client.register_user(name, secrets.token_urlsafe(24)).ok;
    id = rpc(client, "account")["root_id"];
    os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS", "") + "," + id;
}

def prepare(client: JacTestClient, password: str) -> dict[str, any] {
    assert client.register_user("citizen", password).ok;
    rpc(client, "create_report", draft());
    rpc(client, "create_report", draft() | {"latitude": 6.9274});
    assert client.register_user("authority", password).ok;
    os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = rpc(client, "account")["root_id"];
    result = rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24), "mode": "positive"});
    assert result["proposals_created"] == 1;
    assert rpc(client, "confirmed_incidents") == [];
    return rpc(client, "incident_intelligence_state")["proposals"][0];
}
def review_body(proposal: dict[str, any], decision: str = "confirmed") -> dict[str, any] {
    return {"proposal_id": proposal["proposal_id"], "decision": decision, "expected_revision": proposal["revision"]};
}
