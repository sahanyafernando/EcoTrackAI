test "authority accepts one Lead and multiple Supports with durable organization visibility" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client); incident = setup["incident"];
            reports = public_data(rpc(client, "all_reports"));
            orgs = public_data(rpc(client, "organizations"));
            run = coordinate(client, incident);
            assert run["status"] == "completed" and run["organizations_considered"] == 3 and run["llm_requests"] == 1;
            board = rpc(client, "incident_response_board");
            assert len(board["organizations"]) == 3;
            rec = board["incidents"][0]["recommendations"][0];
            lead = rec["lead_organization_id"]; supports = rec["support_organization_ids"];
            assert len(supports) == 2;
            original_request = assignment(client, incident, lead, "lead", run["id"]);
            response = rpc(client, "accept_response", original_request);
            assert response["role"] == "lead" and response["status"] == "active";
            assert not client.post("/function/accept_response", json=original_request).ok;
            for id in supports { rpc(client, "accept_response", assignment(client, incident, id, "support", run["id"])); }
            assert not client.post("/function/accept_response", json=assignment(client, incident, supports[0], "support", run["id"])).ok;
            current = rpc(client, "incident_response_board")["incidents"][0];
            assert current["lead"]["organization_id"] == lead and len(current["supports"]) == 2;
            assert public_data(rpc(client, "all_reports")) == reports;
            assert public_data(rpc(client, "organizations")) == orgs;
            assert len(rpc(client, "confirmed_incidents")) == 1;
            for name in ["first", "second", "third"] {
                client.set_auth_token(setup["tokens"][name]);
                private = rpc(client, "incident_response_board");
                assert not private["authority"] and private["organizations"] == [];
                item = private["incidents"][0];
                assert item["own_role"] == ("lead" if setup["orgs"][name] == lead else "support");
                assert item["recommendations"] == [];
                assert "description" not in item and "report_ids" not in item;
                assert not client.post("/function/all_reports", json={}).ok;
            }
        } finally { client.close(); }
        reopened = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            assert reopened.login("authority", setup["password"]).ok;
            item = rpc(reopened, "incident_response_board")["incidents"][0];
            assert item["lead"]["organization_id"] == lead and len(item["supports"]) == 2;
        } finally { reopened.close(); }
    }
}

test "existing Lead leads to Support recommendations and a second Lead is rejected" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client); incident = setup["incident"];
            first = coordinate(client, incident);
            rec = rpc(client, "incident_response_board")["incidents"][0]["recommendations"][0];
            lead = rec["lead_organization_id"];
            alternative = coordinate(client, incident, "alternate");
            other_lead = rpc(client, "incident_response_board")["incidents"][0]["recommendations"][0]["lead_organization_id"];
            assert other_lead != lead;
            rpc(client, "accept_response", assignment(client, incident, lead, "lead", first["id"]));
            # Both organizations have genuine lead recommendations. Ownership wins
            # even when the second caller supplies the latest Incident revision.
            assert not client.post("/function/accept_response", json=assignment(client, incident, other_lead, "lead", alternative["id"])).ok;
            second = coordinate(client, incident);
            assert second["existing_lead_id"] == lead and second["organizations_considered"] == 2;
            assert "Join as Support" in second["summary"];
            rec = rpc(client, "incident_response_board")["incidents"][0]["recommendations"][0];
            assert rec["lead_organization_id"] == "" and len(rec["support_organization_ids"]) == 2;
            assert not client.post("/function/accept_response", json=assignment(client, incident, rec["support_organization_ids"][0], "lead", first["id"])).ok;
            invalid = coordinate(client, incident, "duplicate_lead"); assert invalid["status"] == "failed";
            current = rpc(client, "incident_response_board")["incidents"][0];
            assert current["lead"]["organization_id"] == lead;
            rpc(client, "accept_response", assignment(client, incident, rec["support_organization_ids"][0], "support", second["id"]));
            assert len(rpc(client, "incident_response_board")["incidents"][0]["supports"]) == 1;
        } finally { client.close(); }
    }
}

test "anonymous Citizen and all Organization roles cannot assign or trigger agent" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client); incident = setup["incident"];
            body = assignment(client, incident, setup["orgs"]["first"], "lead", "forged-run");
            for token in ["", setup["citizen"]] + list(setup["tokens"].values()) {
                client.set_auth_token(token);
                assert not client.post("/function/accept_response", json=body | {"capabilities": ["response:assign"]}).ok;
                assert not client.post("/function/coordinate_response", json={"incident_id": incident, "request_id": secrets.token_urlsafe(24)}).ok;
            }
            for state in ["pending", "rejected", "suspended"] {
                client.set_auth_token(setup["tokens"][state]);
                board = rpc(client, "incident_response_board");
                assert board["incidents"] == [] and board["organization_status"] == state;
                assert "response:read" not in rpc(client, "account")["capabilities"];
            }
            client.set_auth_token(setup["authority"]);
            assert rpc(client, "incident_response_board")["incidents"][0]["lead"] is None;
        } finally { client.close(); }
    }
}

test "stale recommendation cannot assign a newly suspended organization" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client); incident = setup["incident"];
            run = coordinate(client, incident);
            rec = rpc(client, "incident_response_board")["incidents"][0]["recommendations"][0];
            lead = rec["lead_organization_id"];
            rpc(client, "review", {"organization_id": lead, "decision": "suspended", "expected_revision": 2});
            assert not client.post("/function/accept_response", json=assignment(client, incident, lead, "lead", run["id"])).ok;
            assert rpc(client, "incident_response_board")["incidents"][0]["lead"] is None;
            for state in ["pending", "suspended", "rejected"] {
                assert not client.post("/function/accept_response", json=assignment(client, incident, setup["orgs"][state], "support", run["id"])).ok;
            }
        } finally { client.close(); }
    }
}

test "failed malformed and replayed coordination requests are safe and audited" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client); incident = setup["incident"];
            for mode in ["failure", "unknown"] {
                run = coordinate(client, incident, mode);
                assert run["status"] == "failed" and "secret" not in run["error_summary"];
            }
            key = secrets.token_urlsafe(24);
            body = {"incident_id": incident, "request_id": key};
            first = rpc(client, "fixture_coordination", body);
            again = rpc(client, "fixture_coordination", body | {"mode": "failure"}); assert first["id"] == again["id"];
            state = rpc(client, "incident_intelligence_state");
            assert len([item for item in state["runs"] if item["agent_name"] == "Response Coordination Agent"]) == 3;
            assert len([item for item in state["decisions"] if item["decision_type"].startswith("response_")]) == 3;
            assert rpc(client, "incident_response_board")["incidents"][0]["lead"] is None;
            assert not client.post("/function/coordinate_response", json={"incident_id": "missing", "request_id": secrets.token_urlsafe(24)}).ok;
        } finally { client.close(); }
    }
}

test "no verified organizations returns a clean audited result without a model call" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, False);
            run = coordinate(client, setup["incident"], "failure");
            assert run["status"] == "completed" and run["llm_requests"] == 0 and run["organizations_considered"] == 0;
        } finally { client.close(); }
    }
}
