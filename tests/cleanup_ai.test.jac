test "Lead runs real byLLM MockLLM structured assessment with trusted 8 3 5 inputs and persists audits" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        password = secrets.token_urlsafe(24);
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = setup_three(client, password);
            client.set_auth_token(setup["authority"]);
            reports = public_data(rpc(client, "all_reports")); orgs = public_data(rpc(client, "organizations"));
            incidents = public_data(rpc(client, "confirmed_incidents")); responses = public_data(rpc(client, "incident_response_board"));
            events = public_data(rpc(client, "cleanup_events"));
            client.set_auth_token(setup["lead"]);
            key = secrets.token_urlsafe(24); result = plan(client, setup["event"], "assert_three", key);
            assert result["status"] == "completed" and result["llm_requests"] == 1;
            assert result["agent_name"] == "Cleanup & Volunteer Agent";
            assert result["cleanup_event_id"] == setup["event"] and result["incident_id"] == setup["incident"];
            assert result["cleanup_input"]["joined_volunteers"] == 3;
            assessment = result["cleanup_assessment"];
            assert assessment["risk_level"] == "high" and assessment["shortage_detected"];
            assert assessment["volunteers_missing"] == 5 and assessment["recommendation_type"] == "combined_recovery";
            assert len(assessment["support_organization_ids"]) == 1 and len(assessment["recommended_actions"]) == 2;
            assert plan(client, setup["event"], "failure", key)["id"] == result["id"];
            latest = rpc(client, "cleanup_ai_assessments");
            assert len(latest) == 1 and not latest[0]["stale"];
            client.set_auth_token(setup["authority"]);
            assert public_data(rpc(client, "all_reports")) == reports;
            assert public_data(rpc(client, "organizations")) == orgs;
            assert public_data(rpc(client, "confirmed_incidents")) == incidents;
            assert public_data(rpc(client, "incident_response_board")) == responses;
            assert public_data(rpc(client, "cleanup_events")) == events;
            state = rpc(client, "incident_intelligence_state");
            runs = [item for item in state["runs"] if item["agent_name"] == "Cleanup & Volunteer Agent"];
            decisions = [item for item in state["decisions"] if item["cleanup_event_id"] == setup["event"]];
            assert len(runs) == 1 and len(decisions) == 1;
            assert decisions[0]["cleanup_assessment"]["volunteers_missing"] == 5;
            assert decisions[0]["cleanup_input"]["required_volunteers"] == 8;
            assert len(rpc(client, "cleanup_ai_assessments")) == 1;
        } finally { client.close(); }
        reopened = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            assert reopened.login(setup["lead_name"], password).ok;
            saved = rpc(reopened, "cleanup_ai_assessments")[0];
            assert saved["run_id"] == result["id"] and saved["assessment"]["volunteers_missing"] == 5;
        } finally { reopened.close(); }
    }
}

test "anonymous Citizen Support unverified suspended and Authority-only accounts cannot run Cleanup AI" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = setup_three(client, secrets.token_urlsafe(24));
            for token in ["", setup["citizen"], setup["support"], setup["pending"], setup["suspended"], setup["authority"]] {
                client.set_auth_token(token);
                response = client.post("/function/run_cleanup_ai", json={"event_id": setup["event"], "request_id": secrets.token_urlsafe(24), "capabilities": ["agent:plan_cleanup"]});
                assert not response.ok;
                if not token { assert response.status_code == 401; }
                elif token != setup["authority"] { assert rpc(client, "cleanup_ai_assessments") == []; }
            }
            client.set_auth_token(setup["lead"]); assert plan(client, setup["event"])["status"] == "completed";
            client.set_auth_token(setup["authority"]);
            rpc(client, "review", {"organization_id": setup["lead_id"], "decision": "suspended", "expected_revision": 2});
            client.set_auth_token(setup["lead"]);
            assert not client.post("/function/run_cleanup_ai", json={"event_id": setup["event"], "request_id": secrets.token_urlsafe(24)}).ok;
        } finally { client.close(); }
    }
}

test "each new run rereads joining withdrawal and stale previous assessments" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = setup_three(client, secrets.token_urlsafe(24)); event = setup["event"];
            first = plan(client, event); assert first["cleanup_assessment"]["volunteers_missing"] == 5;
            # This account also has its normal personal Citizen participation capability.
            rpc(client, "join_cleanup", {"event_id": event});
            assert rpc(client, "cleanup_ai_assessments")[0]["stale"];
            second = plan(client, event); assert second["cleanup_input"]["joined_volunteers"] == 4;
            assert second["cleanup_assessment"]["volunteers_missing"] == 4;
            client.set_auth_token(setup["citizen"]); rpc(client, "withdraw_cleanup", {"event_id": event});
            client.set_auth_token(setup["lead"]);
            third = plan(client, event); assert third["cleanup_assessment"]["volunteers_missing"] == 5;
            latest = rpc(client, "cleanup_ai_assessments");
            assert len(latest) == 1 and latest[0]["run_id"] == third["id"] and not latest[0]["stale"];
            client.set_auth_token(setup["authority"]);
            runs = [item for item in rpc(client, "incident_intelligence_state")["runs"] if item["cleanup_event_id"] == event];
            assert len(runs) == 3 and all([item["llm_requests"] == 1 for item in runs]);
        } finally { client.close(); }
    }
}

test "invalid shortage risk type and organization references are rejected without operational mutation" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = setup_three(client, secrets.token_urlsafe(24)); event = setup["event"];
            for mode in ["wrong_missing", "unknown_support", "lead_as_support", "duplicate_support", "invalid_risk", "invalid_type", "wrong_shortage"] {
                result = plan(client, event, mode);
                assert result["status"] == "failed" and result["error_category"] == "invalid_output", str(result);
                assert result["cleanup_assessment"] is None;
                assert rpc(client, "cleanup_capacity", {"event_id": event})["joined"] == 3;
            }
            assert rpc(client, "cleanup_events")["events"][0]["status"] == "planned";
            assert rpc(client, "cleanup_ai_assessments")[0]["assessment"] is None;
        } finally { client.close(); }
    }
}

test "model timeout provider failure and missing configuration preserve counts and record safe categories" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        previous = os.environ.get("BYLLM_DEFAULT_MODEL");
        try {
            setup = setup_three(client, secrets.token_urlsafe(24)); event = setup["event"];
            for (mode, category) in [("failure", "provider_error"), ("timeout", "timeout")] {
                failed = plan(client, event, mode);
                assert failed["status"] == "failed" and failed["error_category"] == category;
                assert "secret" not in str(failed) and "Private" not in str(failed);
            }
            os.environ["BYLLM_DEFAULT_MODEL"] = "";
            missing = rpc(client, "run_cleanup_ai", {"event_id": event, "request_id": secrets.token_urlsafe(24)});
            assert missing["status"] == "failed" and missing["error_category"] == "configuration";
            assert rpc(client, "cleanup_capacity", {"event_id": event})["remaining"] == 5;
            assert rpc(client, "cleanup_ai_assessments")[0]["status"] == "failed";
            assert plan(client, event)["status"] == "completed";
        } finally {
            client.close();
            if previous is None { os.environ.pop("BYLLM_DEFAULT_MODEL", None); }
            else { os.environ["BYLLM_DEFAULT_MODEL"] = previous; }
        }
    }
}

test "post-model stale event state is rejected and closed events make no model request" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = setup_three(client, secrets.token_urlsafe(24)); event = setup["event"];
            stale = plan(client, event, "stale_event");
            assert stale["status"] == "failed" and stale["error_category"] == "stale_state";
            assert stale["cleanup_assessment"] is None;
            closed = plan(client, event, "failure");
            assert closed["status"] == "failed" and closed["error_category"] == "invalid_state";
            assert closed["llm_requests"] == 0;
            assert rpc(client, "cleanup_capacity", {"event_id": event})["joined"] == 3;
        } finally { client.close(); }
    }
}
