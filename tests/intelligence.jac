"""Offline deterministic/unit and isolated native graph integration fixtures."""
import os;
import secrets;
import tempfile;
import from contracts.report_views { ReportView }
import from core.intelligence { IntelligenceConfig, CandidateGroup, ClusterAssessment,
    calculate_report_distance, candidate_signal, find_candidate_reports, validate_assessment,
    intelligence_config }
import from jaclang.testing.testing { JacTestClient }
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


def observation(id: str, latitude: float = 6.9271, longitude: float = 79.8612,
                category: str = "illegal_dumping", stamp: str = "2026-10-17T00:00:00+00:00",
                status: str = "submitted", description: str = "Waste beside canal bridge",
                location_text: str = "Bridge") -> ReportView {
    return ReportView(id=id, description=description, category=category,
        latitude=latitude, longitude=longitude, location_text=location_text, evidence_ref="",
        submitted_at=stamp, status=status, created_at=stamp, updated_at=stamp, revision=1);
}

def lifecycle(mode: str, expected_status: str, expected_proposals: int) -> None {
    previous = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS", "");
    os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = "";
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        password = secrets.token_urlsafe(24);
        try {
            assert client.register_user("citizen_a", password).ok;
            first = rpc(client, "create_report", draft());
            citizen_token = client._auth_token or "";
            assert client.register_user("citizen_b", password).ok;
            second = rpc(client, "create_report", draft() | {"description": "Plastic dumped beside the canal bridge", "latitude": 6.9274});
            assert client.register_user("citizen_c", password).ok;
            third = rpc(client, "create_report", draft() | {"latitude": 6.9277});
            distant = rpc(client, "create_report", draft() | {"latitude": 6.99, "category": "blocked_drain"});
            assert client.register_user("authority", password).ok;
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = rpc(client, "account")["root_id"];
            authority_token = client._auth_token or "";
            before = rpc(client, "all_reports");
            key = secrets.token_urlsafe(24);
            run = rpc(client, "fixture_analysis", {"request_id": key, "mode": mode});
            assert run["status"] == expected_status, str(run);
            assert run["reports_examined"] == 4;
            assert run["candidate_relationships"] == 3;
            assert run["candidate_groups_examined"] == 1;
            assert run["llm_requests"] == 1;
            assert run["proposals_created"] == expected_proposals;
            assert run["completed_at"] != "";
            state = rpc(client, "incident_intelligence_state");
            assert len(state["runs"]) == 1;
            assert len(state["proposals"]) == expected_proposals;
            assert len(state["decisions"]) == 1;
            if expected_status == "failed" {
                assert run["error_summary"] != "";
                assert "secret" not in str(state);
                assert state["decisions"][0]["decision_type"] == "assessment_failed";
            }
            if expected_proposals {
                proposal = state["proposals"][0];
                assert proposal["report_ids"] == sorted([first["id"], second["id"], third["id"]]);
                assert distant["id"] not in proposal["report_ids"];
                assert proposal["status"] == "pending_review";
                assert proposal["agent_run_id"] == run["id"];
                assert len(proposal["reports"]) == 3;
                assert len(proposal["signals"]) == 3;
                assert all([signal["category_relation"] == "same" for signal in proposal["signals"]]);
                assert proposal["revision"] == 1;
                assert "reporter_id" not in str(proposal);
                # Exact same report set, new request: no model call or second proposal.
                again = rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24), "mode": "failure"});
                assert again["status"] == "completed";
                assert again["proposals_created"] == 0;
                assert again["llm_requests"] == 0;
                assert len(rpc(client, "incident_intelligence_state")["proposals"]) == 1;
            }
            # Request replay cannot invoke another assessor or create another run.
            replay = rpc(client, "fixture_analysis", {"request_id": key, "mode": "failure"});
            assert replay["id"] == run["id"];
            assert replay["status"] == expected_status;
            assert public_data(rpc(client, "all_reports")) == public_data(before);
            client.set_auth_token(citizen_token);
            assert public_data(rpc(client, "get_report", {"report_id": first["id"]})) == public_data(first);
            assert not client.post("/function/incident_intelligence_state", json={}).ok;
            client.set_auth_token(authority_token);
        } finally {
            client.close();
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = previous;
        }
        # New native server context reopens the persisted graph; no process-local records.
        reopened = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            assert reopened.login("authority", password).ok;
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = rpc(reopened, "account")["root_id"];
            assert len(rpc(reopened, "incident_intelligence_state")["proposals"]) == expected_proposals;
        } finally { reopened.close(); os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = previous; }
    }
}

def public_data(value: any) -> any {
    if isinstance(value, dict) { return {key: public_data(item) for (key, item) in value.items() if not key.startswith("_jac_")}; }
    if isinstance(value, list) { return [public_data(item) for item in value]; }
    return value;
}
