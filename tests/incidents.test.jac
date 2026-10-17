test "authority confirmation creates one persistent Incident and preserves all source reports" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        password = secrets.token_urlsafe(24);
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            proposal = prepare(client, password);
            before = public_data(rpc(client, "all_reports"));
            reviewer = rpc(client, "account")["root_id"];
            # A different authority from the proposal's owner may review it.
            authority(client, "second_authority");
            reviewer = rpc(client, "account")["root_id"];
            result = rpc(client, "review_cluster", review_body(proposal));
            incidents = rpc(client, "confirmed_incidents"); assert len(incidents) == 1;
            item = incidents[0];
            assert result["incident_id"] == item["incident_id"];
            assert item["report_ids"] == proposal["report_ids"];
            assert item["category"] == proposal["suggested_category"];
            assert item["severity"] == proposal["suggested_severity"];
            assert item["status"] == "confirmed" and item["revision"] == 1;
            assert item["confirmed_by"] == reviewer and item["confirmed_at"] != "";
            assert item["created_at"] == item["updated_at"] == item["confirmed_at"];
            assert item["source_proposal_id"] == proposal["proposal_id"];
            reviewed = rpc(client, "incident_intelligence_state")["proposals"][0];
            assert reviewed["status"] == "confirmed" and reviewed["revision"] == 2;
            assert reviewed["reviewed_by"] == reviewer and reviewed["incident_id"] == item["incident_id"];
            assert reviewed["reviewed_at"] == item["confirmed_at"];
            assert public_data(rpc(client, "all_reports")) == before;
            assert len(rpc(client, "incident_human_reviews")) == 1;
            assert result["previous_status"] == "pending_review" and result["proposal_revision"] == 2;
            # Both stale retries and retries with the latest revision are refused.
            assert not client.post("/function/review_cluster", json=review_body(proposal)).ok;
            assert not client.post("/function/review_cluster", json=review_body(reviewed)).ok;
            assert not client.post("/function/review_cluster", json=review_body(reviewed, "rejected")).ok;
            assert len(rpc(client, "confirmed_incidents")) == 1;
            assert len(rpc(client, "incident_human_reviews")) == 1;
            client.set_auth_token(""); assert client.login("citizen", password).ok;
            assert len(rpc(client, "my_reports")) == 2;
        } finally { client.close(); }
        reopened = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            assert reopened.login("authority", password).ok;
            assert len(rpc(reopened, "confirmed_incidents")) == 1;
            assert rpc(reopened, "confirmed_incidents")[0]["source_proposal_id"] == proposal["proposal_id"];
            assert len(rpc(reopened, "incident_human_reviews")) == 1;
        } finally { reopened.close(); }
    }
}

test "rejected proposal creates no Incident and cannot be revived by intelligence" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            proposal = prepare(client, secrets.token_urlsafe(24));
            before = public_data(rpc(client, "all_reports"));
            result = rpc(client, "review_cluster", review_body(proposal, "rejected"));
            assert result["resulting_status"] == "rejected" and result["incident_id"] == "";
            assert rpc(client, "confirmed_incidents") == [];
            reviewed = rpc(client, "incident_intelligence_state")["proposals"][0];
            assert reviewed["status"] == "rejected" and reviewed["revision"] == 2;
            assert not client.post("/function/review_cluster", json=review_body(reviewed)).ok;
            run = rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24), "mode": "failure"});
            assert run["status"] == "completed" and run["llm_requests"] == 0;
            assert rpc(client, "incident_intelligence_state")["proposals"][0]["status"] == "rejected";
            assert rpc(client, "confirmed_incidents") == [];
            assert public_data(rpc(client, "all_reports")) == before;
        } finally { client.close(); }
    }
}

test "anonymous Citizen applicant and verified organization cannot review or list private Incidents" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        password = secrets.token_urlsafe(24);
        try {
            proposal = prepare(client, password); token = client._auth_token or "";
            client.set_auth_token("");
            assert client.post("/function/review_cluster", json=review_body(proposal)).status_code == 401;
            assert client.post("/function/confirmed_incidents", json={}).status_code == 401;
            assert client.login("citizen", password).ok;
            for decision in ["confirmed", "rejected"] {
                assert not client.post("/function/review_cluster", json=review_body(proposal, decision) | {"capabilities": ["incident:confirm"], "context": "authority"}).ok;
            }
            org = rpc(client, "apply", {"name": "Environment group", "description": "Community group"});
            org_token = client._auth_token or "";
            for verified in [False, True] {
                if verified {
                    client.set_auth_token(token);
                    rpc(client, "review", {"organization_id": org["id"], "decision": "verified", "expected_revision": 1});
                    client.set_auth_token(org_token);
                }
                for decision in ["confirmed", "rejected"] {
                    assert not client.post("/function/review_cluster", json=review_body(proposal, decision)).ok;
                }
                assert not client.post("/function/confirmed_incidents", json={}).ok;
                assert not client.post("/function/incident_human_reviews", json={}).ok;
            }
            client.set_auth_token(token);
            assert rpc(client, "incident_intelligence_state")["proposals"][0]["status"] == "pending_review";
            assert rpc(client, "confirmed_incidents") == [];
        } finally { client.close(); }
    }
}

test "stale unknown and unsupported reviews cause no mutations" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            proposal = prepare(client, secrets.token_urlsafe(24));
            for body in [review_body(proposal) | {"expected_revision": 99},
                review_body(proposal) | {"proposal_id": "missing"}, review_body(proposal, "split")] {
                assert not client.post("/function/review_cluster", json=body).ok;
            }
            assert rpc(client, "confirmed_incidents") == [];
            assert rpc(client, "incident_human_reviews") == [];
            assert rpc(client, "incident_intelligence_state")["proposals"][0]["revision"] == 1;
        } finally { client.close(); }
    }
}

test "an injected model assessor cannot confirm even while running as Authority" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            authority(client);
            rpc(client, "create_report", draft()); rpc(client, "create_report", draft() | {"latitude": 6.9274});
            run = rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24), "mode": "attempt_confirmation"});
            assert run["status"] == "failed";
            assert rpc(client, "confirmed_incidents") == [];
            assert rpc(client, "incident_human_reviews") == [];
            assert len(rpc(client, "all_reports")) == 2;
        } finally { client.close(); }
    }
}

test "reviewed demo evidence cannot be cleared after confirmation or rejection" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            authority(client); rpc(client, "load_demo");
            rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24), "mode": "demo_mock"});
            proposals = rpc(client, "incident_intelligence_state")["proposals"];
            rpc(client, "review_cluster", review_body(proposals[0]));
            rpc(client, "review_cluster", review_body(proposals[1], "rejected"));
            before = public_data(rpc(client, "all_reports"));
            assert not client.post("/function/clear_demo", json={}).ok;
            assert public_data(rpc(client, "all_reports")) == before;
            assert len(rpc(client, "confirmed_incidents")) == 1;
            again = rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24), "mode": "failure"});
            assert again["status"] == "completed" and again["llm_requests"] == 0;
            state = rpc(client, "incident_intelligence_state");
            assert len(state["proposals"]) == 4 and len(rpc(client, "confirmed_incidents")) == 1;
            assert len(rpc(client, "incident_human_reviews")) == 2;
        } finally { client.close(); }
    }
}
