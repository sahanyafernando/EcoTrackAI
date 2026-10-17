test "Authority routes confirmed Incident through native MockLLM to response specialist without changing reports or assigning Lead" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24), False);
            before = public_data(rpc(client, "all_reports"));
            request = secrets.token_urlsafe(24);
            run = coordinate(client, "incident_confirmed", setup["incident"], request=request);
            assert run["status"] == "completed" and run["llm_requests"] == 1;
            assert run["coordinator_decision"]["target_agent"] == "response_coordination";
            assert run["delegation_result"] == "completed" and run["delegated_run_id"];
            board = rpc(client, "incident_response_board")["incidents"][0];
            assert board["lead"] is None and len(board["recommendations"]) == 1;
            assert public_data(rpc(client, "all_reports")) == before;
            replay = coordinate(client, "incident_confirmed", setup["incident"], request=request);
            assert replay["id"] == run["id"];
            assert len(rpc(client, "incident_response_board")["incidents"][0]["recommendations"]) == 1;
            state = rpc(client, "incident_intelligence_state");
            assert any([item["agent_run_id"] == run["id"] and item["decision_type"] == "coordinator_completed" for item in state["decisions"]]);
        } finally { client.close(); }
        reopened = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            reopened.set_auth_token(setup["authority"]);
            assert any([item["id"] == run["id"] and item["delegated_run_id"] for item in rpc(reopened, "incident_intelligence_state")["runs"]]);
        } finally { reopened.close(); }
    }
}

test "Authority cleanup handoff uses 8 3 5 then fresh withdrawal 8 2 6 and Lead can inspect assessment" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24)); event = create(client, setup)["event_id"];
            for token in [setup["citizen"], setup["second"], setup["lead"]] {
                client.set_auth_token(token); rpc(client, "join_cleanup", {"event_id": event});
            }
            client.set_auth_token(setup["authority"]);
            first = coordinate(client, "cleanup_created", event);
            assert first["status"] == "completed" and first["delegation_result"] == "completed";
            assert first["coordinator_input"]["cleanup"]["remaining_volunteers"] == 5;
            latest = rpc(client, "cleanup_ai_assessments")[0];
            assert latest["input_state"]["required_volunteers"] == 8 and latest["input_state"]["joined_volunteers"] == 3;
            assert latest["assessment"]["volunteers_missing"] == 5;
            client.set_auth_token(setup["lead"]);
            assert rpc(client, "cleanup_ai_assessments")[0]["run_id"] == first["delegated_run_id"];
            client.set_auth_token(setup["citizen"]); rpc(client, "withdraw_cleanup", {"event_id": event});
            client.set_auth_token(setup["authority"]);
            second = coordinate(client, "volunteer_state_changed", event);
            assert second["status"] == "completed";
            latest = rpc(client, "cleanup_ai_assessments")[0];
            assert latest["input_state"]["required_volunteers"] == 8 and latest["input_state"]["joined_volunteers"] == 2;
            assert latest["assessment"]["volunteers_missing"] == 6 and not latest["stale"];
            assert second["coordinator_input"]["cleanup"]["remaining_volunteers"] == 6;
        } finally { client.close(); }
    }
}

test "anonymous Citizens Organizations cannot invoke global Coordinator or delegated Authority cleanup mode" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24)); event = create(client, setup)["event_id"];
            for token in ["", setup["citizen"], setup["lead"], setup["support"], setup["pending"], setup["suspended"]] {
                client.set_auth_token(token);
                body = {"event_type": "cleanup_created", "entity_id": event, "request_id": secrets.token_urlsafe(24)};
                assert not client.post("/function/coordinate_workflow", json=body).ok;
                assert not client.post("/function/fixture_coordinator", json=body).ok;
            }
            client.set_auth_token(setup["authority"]);
            assert not client.post("/function/run_cleanup_ai", json={"event_id": event,
                "request_id": secrets.token_urlsafe(24), "authority_delegation": True}).ok;
            client.set_auth_token(setup["support"]);
            assert rpc(client, "cleanup_ai_assessments") == [];
        } finally { client.close(); }
    }
}

test "invalid action target entity and second Lead routing are rejected without delegation or protected mutation" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24));
            before = public_data(rpc(client, "all_reports"));
            for mode in ["invalid_action", "invalid_target", "wrong_entity", "second_lead"] {
                run = coordinate(client, "incident_confirmed", setup["incident"], mode);
                assert run["status"] == "failed" and run["error_category"] == "invalid_output";
                assert run["delegated_run_id"] == "";
            }
            assert public_data(rpc(client, "all_reports")) == before;
            board = rpc(client, "incident_response_board")["incidents"][0];
            assert board["lead"]["organization_id"] == setup["lead_id"];
            no_action = coordinate(client, "incident_confirmed", setup["incident"]);
            assert no_action["status"] == "completed" and no_action["delegation_result"] == "not_delegated";
            assert no_action["coordinator_decision"]["action"] == "no_action";
            review = coordinate(client, "incident_confirmed", setup["incident"], "human_review");
            assert review["status"] == "completed" and review["coordinator_decision"]["action"] == "require_human_review";
        } finally { client.close(); }
    }
}

test "Coordinator and specialist provider failures persist safe failed audits without corruption" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24)); event = create(client, setup)["event_id"];
            client.set_auth_token(setup["authority"]);
            for mode in ["failure", "timeout", "specialist_failure"] {
                run = coordinate(client, "cleanup_created", event, mode);
                assert run["status"] == "failed" and "Private" not in run["error_summary"];
                if mode == "specialist_failure" {
                    assert run["error_category"] == "delegation_failed" and run["delegated_run_id"];
                    assert run["delegation_result"] == "failed";
                } else { assert run["delegated_run_id"] == ""; }
            }
            assert rpc(client, "cleanup_capacity", {"event_id": event})["remaining"] == 8;
            assert len(rpc(client, "confirmed_incidents")) == 1;
        } finally { client.close(); }
    }
}
