test "verified Lead creates one persistent official cleanup with public capacity and private participation" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        password = secrets.token_urlsafe(24);
        try {
            setup = prepare(client, password); event = create(client, setup);
            assert event["status"] == "planned" and event["revision"] == 1 and event["can_manage"];
            assert event["lead_organization_id"] == setup["lead_id"] and event["incident_id"] == setup["incident"];
            assert event["required_volunteers"] == 8 and event["joined_volunteers"] == 0 and event["remaining_needed"] == 8;
            assert event["created_at"] == event["updated_at"] and event["scheduled_at"] != "";
            assert not client.post("/function/create_cleanup_event", json=draft(setup["incident"])).ok;
            assert len(rpc(client, "cleanup_events")["events"]) == 1;
            assert rpc(client, "cleanup_events")["lead_incidents"] == [];
            client.set_auth_token(setup["authority"]);
            assert len(rpc(client, "cleanup_events")["events"]) == 1;
            client.set_auth_token(setup["citizen"]);
            rpc(client, "join_cleanup", {"event_id": event["event_id"]});
            public = rpc(client, "cleanup_events");
            assert "user_id" not in str(public) and "participants" not in public["events"][0];
        } finally { client.close(); }
        reopened = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            assert reopened.login("citizen_a", password).ok;
            saved = rpc(reopened, "cleanup_events")["events"][0];
            assert saved["event_id"] == event["event_id"] and saved["joined_volunteers"] == 1 and saved["my_participation"] == "joined";
            assert not saved["can_manage"];
        } finally { reopened.close(); }
    }
}

test "anonymous Citizen Support pending and suspended organization cannot create official events" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24));
            for token in ["", setup["citizen"], setup["support"], setup["pending"], setup["suspended"], setup["authority"]] {
                client.set_auth_token(token);
                assert not client.post("/function/create_cleanup_event", json=draft(setup["incident"]) | {"lead_organization_id": setup["lead_id"]}).ok;
            }
            event = create(client, setup);
            client.set_auth_token("");
            for endpoint in ["cleanup_events", "join_cleanup", "withdraw_cleanup", "cleanup_capacity"] {
                assert client.post("/function/" + endpoint, json={"event_id": event["event_id"]}).status_code == 401;
            }
        } finally { client.close(); }
    }
}

test "three Citizens join exactly once withdraw only themselves and rejoin without duplicate counts" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24)); event = create(client, setup); body = {"event_id": event["event_id"]};
            client.set_auth_token(setup["citizen"]);
            a_root = rpc(client, "account")["root_id"];
            joined = rpc(client, "join_cleanup", body); assert joined["joined_volunteers"] == 1;
            assert not client.post("/function/join_cleanup", json=body).ok;
            client.set_auth_token(setup["second"]);
            assert not client.post("/function/withdraw_cleanup", json=body | {"user_id": a_root}).ok;
            assert rpc(client, "cleanup_capacity", body)["joined"] == 1;
            rpc(client, "join_cleanup", body);
            assert client.register_user("citizen_c", secrets.token_urlsafe(24)).ok;
            result = rpc(client, "join_cleanup", body);
            assert result["required_volunteers"] == 8 and result["joined_volunteers"] == 3 and result["remaining_needed"] == 5;
            client.set_auth_token(setup["citizen"]);
            result = rpc(client, "withdraw_cleanup", body);
            assert result["my_participation"] == "withdrawn" and result["joined_volunteers"] == 2 and result["remaining_needed"] == 6;
            assert not client.post("/function/withdraw_cleanup", json=body).ok;
            rpc(client, "join_cleanup", body);
            capacity = rpc(client, "cleanup_capacity", body);
            assert capacity["required"] == 8 and capacity["joined"] == 3 and capacity["remaining"] == 5;
            client.set_auth_token(setup["lead"]);
            assert rpc(client, "cleanup_events")["events"][0]["joined_volunteers"] == 3;
        } finally { client.close(); }
    }
}

test "only current Lead manages status with revisions and closed events reject new joins" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24)); event = create(client, setup);
            body = {"event_id": event["event_id"], "status": "active", "expected_revision": 1};
            for token in [setup["citizen"], setup["support"], setup["pending"], setup["suspended"], setup["authority"]] {
                client.set_auth_token(token); assert not client.post("/function/manage_cleanup_event", json=body).ok;
            }
            client.set_auth_token(setup["citizen"]); rpc(client, "join_cleanup", {"event_id": event["event_id"]});
            client.set_auth_token(setup["lead"]);
            active = rpc(client, "manage_cleanup_event", body); assert active["status"] == "active" and active["revision"] == 2;
            assert not client.post("/function/manage_cleanup_event", json=body | {"status": "cancelled"}).ok;
            done = rpc(client, "manage_cleanup_event", body | {"status": "completed", "expected_revision": 2});
            assert done["status"] == "completed";
            assert not client.post("/function/manage_cleanup_event", json=body | {"status": "active", "expected_revision": 3}).ok;
            client.set_auth_token(setup["second"]);
            assert not client.post("/function/join_cleanup", json={"event_id": event["event_id"]}).ok;
            client.set_auth_token(setup["citizen"]);
            assert rpc(client, "withdraw_cleanup", {"event_id": event["event_id"]})["joined_volunteers"] == 0;
        } finally { client.close(); }
    }
}

test "event validation rejects invalid fields before any event is created" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24)); client.set_auth_token(setup["lead"]);
            for invalid in [{"title": " "}, {"description": ""}, {"location_text": ""}, {"latitude": 91}, {"longitude": -181},
                {"required_volunteers": 0}, {"required_volunteers": 1001}, {"scheduled_at": "bad-date"},
                {"scheduled_at": "2030-01-01T10:00:00"}, {"scheduled_at": "2020-01-01T10:00:00+00:00"}] {
                assert not client.post("/function/create_cleanup_event", json=draft(setup["incident"]) | invalid).ok;
            }
            assert rpc(client, "cleanup_events")["events"] == [];
            event = create(client, setup);
            assert not client.post("/function/join_cleanup", json={"event_id": "missing"}).ok;
            cancelled = rpc(client, "manage_cleanup_event", {"event_id": event["event_id"], "status": "cancelled", "expected_revision": 1});
            assert cancelled["status"] == "cancelled";
            assert not client.post("/function/join_cleanup", json={"event_id": event["event_id"]}).ok;
        } finally { client.close(); }
    }
}

test "suspending a Lead removes cleanup management immediately" {
    with AuthorityEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            setup = prepare(client, secrets.token_urlsafe(24)); event = create(client, setup);
            client.set_auth_token(setup["authority"]);
            rpc(client, "review", {"organization_id": setup["lead_id"], "decision": "suspended", "expected_revision": 2});
            client.set_auth_token(setup["lead"]);
            assert not rpc(client, "cleanup_events")["events"][0]["can_manage"];
            assert not client.post("/function/manage_cleanup_event", json={"event_id": event["event_id"], "status": "cancelled", "expected_revision": 1}).ok;
            assert "cleanup:manage" not in rpc(client, "account")["capabilities"];
        } finally { client.close(); }
    }
}
