test "report lifecycle ownership authority and organization isolation" {
    previous = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS", "");
    os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = "";
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        password = secrets.token_urlsafe(24);
        try {
            body = draft();
            for endpoint in ["create_report", "my_reports", "all_reports", "get_report", "report_categories"] {
                anonymous = client.post("/function/" + endpoint, json=body | {"report_id": "unknown"});
                assert anonymous.status_code == 401, anonymous.text;
            }
            assert client.register_user("reporter", password).ok;
            reporter_token = client._auth_token or "";
            assert rpc(client, "report_categories") == list(REPORT_CATEGORIES);
            assert rpc(client, "my_reports") == [];
            created = rpc(client, "create_report", body);
            assert created["id"] != "";
            assert created["status"] == "submitted";
            assert created["revision"] == 1;
            assert created["submitted_at"] == created["created_at"];
            assert created["created_at"] == created["updated_at"];
            assert created["latitude"] == body["latitude"];
            assert created["location_text"] == body["location_text"];
            assert created["evidence_ref"] == "";
            assert "reporter_id" not in created;
            assert "submission_id" not in created;
            assert rpc(client, "get_report", {"report_id": created["id"]})["description"] == body["description"];
            assert rpc(client, "my_reports")[0]["id"] == created["id"];
            assert rpc(client, "create_report", body)["id"] == created["id"];
            assert len(rpc(client, "my_reports")) == 1;
            assert not client.post("/function/create_report", json=body | {"description": "Changed retry"}).ok;
            # Validation must run in the core even for hand-written authenticated HTTP requests.
            for change in [{"category": "invented"}, {"description": " "}, {"latitude": 91.0}, {"longitude": -181.0}] {
                assert not client.post("/function/create_report", json=body | change).ok;
            }
            assert len(rpc(client, "my_reports")) == 1;
            assert not client.post("/function/all_reports", json={}).ok;
            client.clear_auth();
            assert client.login("reporter", password).ok;
            assert rpc(client, "get_report", {"report_id": created["id"]})["id"] == created["id"];

            assert client.register_user("org_user", password).ok;
            org_token = client._auth_token or "";
            assert rpc(client, "my_reports") == [];
            assert not client.post("/function/get_report", json={"report_id": created["id"]}).ok;
            application = rpc(client, "apply", {"name": "Local Organization", "description": "Application"});
            assert not client.post("/function/all_reports", json={}).ok;
            org_report = rpc(client, "create_report", draft());
            assert len(rpc(client, "my_reports")) == 1;
            assert org_report["id"] != created["id"];

            assert client.register_user("authority", password).ok;
            authority_root = rpc(client, "account")["root_id"];
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = authority_root;
            all_items = rpc(client, "all_reports");
            assert len(all_items) == 2;
            assert {item["id"] for item in all_items} == {created["id"], org_report["id"]};
            assert rpc(client, "my_reports") == [];
            assert rpc(client, "get_report", {"report_id": created["id"]})["description"] == body["description"];
            rpc(client, "review", {"organization_id": application["id"], "decision": "verified", "expected_revision": 1});
            client.set_auth_token(org_token);
            assert "organization:verified_member" in rpc(client, "account")["capabilities"];
            assert not client.post("/function/all_reports", json={}).ok;
            assert not client.post("/function/get_report", json={"report_id": created["id"]}).ok;
            assert len(rpc(client, "my_reports")) == 1;
            client.set_auth_token(reporter_token);
            assert not client.post("/function/get_report", json={"report_id": org_report["id"]}).ok;
            assert not client.post("/function/get_report", json={"report_id": "made-up-id"}).ok;
        } finally {
            client.close();
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = previous;
        }
    }
}

test "report persists after reopening native server and login" {
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        password = secrets.token_urlsafe(24);
        try {
            assert client.register_user("persistent", password).ok;
            original = rpc(client, "create_report", draft());
        } finally { client.close(); }
        reopened = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            assert reopened.login("persistent", password).ok;
            restored = rpc(reopened, "get_report", {"report_id": original["id"]});
            assert restored["id"] == original["id"];
            assert restored["description"] == original["description"];
            assert len(rpc(reopened, "my_reports")) == 1;
        } finally { reopened.close(); }
    }
}

test "concurrent retries create only one report" {
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            assert client.register_user("replay", secrets.token_urlsafe(24)).ok;
            rpc(client, "account");
            body = draft();
            with ThreadPoolExecutor(max_workers=2) as pool {
                a = pool.submit(client.post, "/function/create_report", json=body);
                b = pool.submit(client.post, "/function/create_report", json=body);
                outcomes = [a.result(), b.result()];
                assert any(response.ok for response in outcomes);
            }
            saved = rpc(client, "create_report", body);
            assert len(rpc(client, "my_reports")) == 1;
            for response in outcomes {
                if response.ok { assert response.json()["data"]["result"]["id"] == saved["id"]; }
            }
        } finally { client.close(); }
    }
}

test "coordinate boundaries and all canonical categories are accepted" {
    for category in REPORT_CATEGORIES {
        validate_report("Observation", category, -90.0, -180.0, "", "boundary-request-key");
        validate_report("Observation", category, 90.0, 180.0, "", "boundary-request-key");
        validate_report("Observation", category, 0.0, 0.0, "", "boundary-request-key");
    }
}

test "client workspace state cannot grant authority capabilities" {
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            assert client.register_user("navigation_citizen", secrets.token_urlsafe(24)).ok;
            before = rpc(client, "account");
            response = client.post("/function/review", json={
                "organization_id": "unknown", "decision": "verified", "expected_revision": 1,
                "workspace": "authority", "page": "review", "capabilities": ["organization:verify"]
            });
            assert not response.ok;
            assert not client.post("/function/all_reports", json={"workspace": "authority"}).ok;
            after = rpc(client, "account");
            assert "organization:verify" not in after["capabilities"];
            assert "report:read_all" not in after["capabilities"];
            assert before["capabilities"] == after["capabilities"];
        } finally { client.close(); }
    }
}
