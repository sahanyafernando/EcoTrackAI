test "authenticated organization lifecycle and isolation" {
    previous = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS", "");
    os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = "";
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        password = secrets.token_urlsafe(24);
        try {
            # Every exposed domain operation rejects anonymous requests.
            for name in ["account", "apply", "edit_organization", "organizations", "review"] {
                response = client.post("/function/" + name, json={"name": "Test", "description": "Test", "organization_id": "unknown", "decision": "verified", "expected_revision": 1});
                assert response.status_code == 401, response.text;
            }
            assert client.register_user("applicant", password).ok;
            assert client.login("applicant", password).ok;
            applicant_token = client._auth_token;
            profile = rpc(client, "account", {"display_name": "Applicant"});
            again = rpc(client, "account", {"display_name": "Do not replace"});
            assert profile["root_id"] == again["root_id"];
            assert profile["created_at"] == again["created_at"];
            assert again["display_name"] == "Applicant";
            assert again["revision"] == 1;
            assert not again["volunteer_enabled"];
            org = rpc(client, "apply", {"name": "River Group", "description": "Local environmental organization"});
            assert org["verification_status"] == "pending";
            assert rpc(client, "account")["organization"]["id"] == org["id"];
            assert not client.post("/function/apply", json={"name": "Duplicate", "description": "Duplicate"}).ok;
            decision = {"organization_id": org["id"], "decision": "verified", "expected_revision": 1};
            assert not client.post("/function/review", json=decision).ok;
            assert not client.post("/function/organizations", json={}).ok;
            edited = rpc(client, "edit_organization", {"organization_id": org["id"], "name": "River Team", "description": "Updated details", "expected_revision": 1});
            assert edited["revision"] == 2;
            assert not client.post("/function/edit_organization", json={"organization_id": org["id"], "name": "Stale", "description": "Stale", "expected_revision": 1}).ok;

            assert client.register_user("citizen", password).ok;
            citizen_token = client._auth_token;
            citizen = rpc(client, "account");
            assert citizen["organization"] is None;
            assert not client.post("/function/review", json=decision).ok;
            assert not client.post("/function/edit_organization", json={"organization_id": org["id"], "name": "Attack", "description": "Attack", "expected_revision": 2}).ok;
            rejected_org = rpc(client, "apply", {"name": "Second Group", "description": "Separate application"});

            assert client.register_user("reviewer", password).ok;
            authority = rpc(client, "account");
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = authority["root_id"];
            assert "organization:verify" in rpc(client, "account")["capabilities"];
            assert len(rpc(client, "organizations")) == 2;
            # Authority capability never permits self-review either.
            authority_org = rpc(client, "apply", {"name": "Reviewer Group", "description": "No self approval"});
            assert not client.post("/function/review", json={"organization_id": authority_org["id"], "decision": "verified", "expected_revision": 1}).ok;
            # Stale review leaves the application pending.
            assert not client.post("/function/review", json=decision).ok;
            verified = rpc(client, "review", {"organization_id": org["id"], "decision": "verified", "expected_revision": 2});
            assert verified["verification_status"] == "verified";
            assert verified["verified_by"] == authority["root_id"];
            assert verified["verified_at"] != "";
            rejected = rpc(client, "review", {"organization_id": rejected_org["id"], "decision": "rejected", "expected_revision": 1});
            assert rejected["verification_status"] == "rejected";
            authority_token = client._auth_token;
            client.set_auth_token(applicant_token or "");
            assert "organization:verified_member" in rpc(client, "account")["capabilities"];
            for status in ["verified", "rejected", "suspended"] {
                assert not client.post("/function/review", json={"organization_id": org["id"], "decision": status, "expected_revision": 3}).ok;
            }
            client.set_auth_token(authority_token or "");
            suspended = rpc(client, "review", {"organization_id": org["id"], "decision": "suspended", "expected_revision": 3});
            assert suspended["verification_status"] == "suspended";
            assert suspended["reviewed_by"] == authority["root_id"];
            assert suspended["revision"] == 4;
            client.set_auth_token(applicant_token or "");
            restored = rpc(client, "account");
            assert restored["organization"]["verification_status"] == "suspended";
            assert "organization:verified_member" not in restored["capabilities"];
            # Config removal takes effect on the next request, even with an existing JWT.
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = "";
            client.set_auth_token(authority_token or "");
            assert not client.post("/function/organizations", json={}).ok;
            client.clear_auth();
            assert client.post("/function/account", json={}).status_code == 401;
            assert client.login("applicant", password).ok;
            assert rpc(client, "account")["root_id"] == profile["root_id"];
        } finally {
            client.close();
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = previous;
    }
}
}

test "concurrent initialization and application remain unique" {
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            assert client.register_user("concurrent", secrets.token_urlsafe(24)).ok;
            with ThreadPoolExecutor(max_workers=2) as pool {
                first = pool.submit(client.post, "/function/account", json={});
                second = pool.submit(client.post, "/function/account", json={});
                a = first.result();
                b = second.result();
                assert a.ok and b.ok;
                assert a.json()["data"]["result"]["created_at"] == b.json()["data"]["result"]["created_at"];
                first_apply = pool.submit(client.post, "/function/apply", json={"name": "One", "description": "First request"});
                second_apply = pool.submit(client.post, "/function/apply", json={"name": "Two", "description": "Second request"});
                outcomes = [first_apply.result(), second_apply.result()];
                assert len([response for response in outcomes if response.ok]) == 1;
            }
            assert rpc(client, "account")["organization"] is not None;
        } finally { client.close(); }
    }
}

test "core domain also rejects anonymous or system root" {
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            client._ensure_initialized();
            Jac.get_context().set_user_root(jid(root.shared));
            with testraises(PermissionError) { ensure_profile(); }
            with testraises(PermissionError) { apply_organization("Denied", "No authenticated user"); }
            with testraises(PermissionError) { review_application("unknown", "verified", 1); }
        } finally {
            client.close();
            # This direct-core test resolves the guest outside HTTP middleware. Jac 0.37.23
            # caches that root in this context; release it before the next isolated database.
            import from jaclang.server.identity.user_manager { _root_id_request_cache }
            _root_id_request_cache.set(None);
            Jac.set_shared_root_resolver(None);
        }
    }
}
