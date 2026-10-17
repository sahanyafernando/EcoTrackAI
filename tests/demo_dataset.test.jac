test "demo is opt in and rejects anonymous citizen organization and disabled authority requests" {
    with DemoEnvironment() {
        os.environ.pop("ECOTRACK_ENABLE_DEMO_SEED", None);
        assert not demo_enabled();
        os.environ["ECOTRACK_ENABLE_DEMO_SEED"] = "false";
        assert not demo_enabled();
        with tempfile.TemporaryDirectory() as directory {
            client = JacTestClient.from_file("main.jac", base_path=directory);
            try {
                for endpoint in ["demo_dataset_status", "load_demo", "clear_demo"] {
                    assert client.post("/function/" + endpoint, json={}).status_code == 401;
                }
                assert client.register_user("citizen", secrets.token_urlsafe(24)).ok;
                os.environ["ECOTRACK_ENABLE_DEMO_SEED"] = "true";
                for endpoint in ["demo_dataset_status", "load_demo", "clear_demo"] {
                    assert not client.post("/function/" + endpoint, json={}).ok;
                }
                rpc(client, "apply", {"name": "Local response", "description": "An applicant"});
                assert not client.post("/function/load_demo", json={"capabilities": ["demo:manage"]}).ok;
                authority(client);
                os.environ["ECOTRACK_ENABLE_DEMO_SEED"] = "false";
                assert not rpc(client, "demo_dataset_status")["enabled"];
                assert not client.post("/function/load_demo", json={}).ok;
                assert not client.post("/function/clear_demo", json={}).ok;
                assert rpc(client, "all_reports") == [];
            } finally { client.close(); }
        }
    }
}

test "sixteen natural observations form four geographically separate complete link groups" {
    rows = synthetic_observations(); assert len(rows) == 16;
    assert len({row.description for row in rows}) == 16;
    stamp = datetime.now(timezone.utc);
    reports: list[ReportView] = [];
    for (index, row) in enumerate(rows) {
        reports.append(ReportView(id=str(index), description=row.description, category=row.category,
            latitude=row.latitude, longitude=row.longitude, location_text=row.location_text,
            evidence_ref="", submitted_at=(stamp - timedelta(minutes=index * 7)).isoformat(),
            status="submitted", created_at=stamp.isoformat(), updated_at=stamp.isoformat(),
            revision=1, source_type="demo_seed", demo_dataset=DEMO_DATASET));
    }
    config = IntelligenceConfig();
    groups = find_candidate_reports(reports, config);
    assert len(groups) == 4;
    # Ground truth is confined to this test, never a field on a Report or agent input.
    expected = [{str(index) for index in range(start, start + 4)} for start in [0, 4, 8, 12]];
    assert all([{item.id for item in group.reports} in expected for group in groups]);
    for first in reports {
        for second in reports {
            if first.id == second.id { continue; }
            if int(first.id) // 4 == int(second.id) // 4 {
                assert 20 <= calculate_report_distance(first, second) <= 120;
                assert candidate_signal(first, second, config) is not None;
            } else {
                assert calculate_report_distance(first, second) > 250;
                assert candidate_signal(first, second, config) is None;
                # Distance alone excludes the pair even if category is made equal.
                saved = second.category; second.category = first.category;
                assert candidate_signal(first, second, config) is None;
                second.category = saved;
            }
        }
    }
}

test "authority seed is idempotent marked private and persistent after reopening" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        password = secrets.token_urlsafe(24);
        client = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            assert client.register_user("authority", password).ok;
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = rpc(client, "account")["root_id"];
            assert rpc(client, "demo_dataset_status")["report_count"] == 0;
            assert rpc(client, "load_demo")["reports_loaded"] == 16;
            reports = rpc(client, "all_reports");
            assert len(reports) == 16;
            assert all([item["source_type"] == "demo_seed" and item["demo_dataset"] == DEMO_DATASET for item in reports]);
            assert all([item["status"] == "submitted" and item["revision"] == 1 for item in reports]);
            assert all(["case_id" not in item and "case_label" not in item for item in reports]);
            assert rpc(client, "my_reports") == [];
            second = rpc(client, "load_demo");
            assert second["message"] == "Demo dataset already loaded.";
            assert public_data(rpc(client, "all_reports")) == public_data(reports);
            assert client.register_user("citizen", secrets.token_urlsafe(24)).ok;
            assert not client.post("/function/get_report", json={"report_id": reports[0]["id"]}).ok;
            genuine = rpc(client, "create_report", real_draft() | {"source_type": "demo_seed", "demo_dataset": DEMO_DATASET});
            assert genuine["source_type"] == "citizen" and genuine["demo_dataset"] == "";
        } finally { client.close(); }
        reopened = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            assert reopened.login("authority", password).ok;
            assert rpc(reopened, "load_demo")["message"] == "Demo dataset already loaded.";
            assert rpc(reopened, "demo_dataset_status")["report_count"] == 16;
            assert len(rpc(reopened, "all_reports")) == 17;
        } finally { reopened.close(); }
    }
}

test "normal agent discovers demo groups offline without changing reports and clear removes pure demo history" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            authority(client); rpc(client, "load_demo");
            before = rpc(client, "all_reports");
            run = rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24), "mode": "demo_mock"});
            assert run["status"] == "completed";
            assert run["reports_examined"] == 16;
            assert run["candidate_relationships"] == 24;
            assert run["candidate_groups_examined"] == 4;
            assert run["llm_requests"] == 1;
            assert run["proposals_created"] == 4;
            state = rpc(client, "incident_intelligence_state");
            assert len(state["proposals"]) == 4;
            assert all([len(item["report_ids"]) == 4 and item["status"] == "pending_review" for item in state["proposals"]]);
            assert public_data(rpc(client, "all_reports")) == public_data(before);
            cleared = rpc(client, "clear_demo");
            assert cleared["reports_removed"] == 16;
            assert cleared["proposals_removed"] == 4;
            assert cleared["decisions_removed"] == 4;
            assert cleared["runs_removed"] == 1;
            assert rpc(client, "all_reports") == [];
            assert not rpc(client, "demo_dataset_status")["loaded"];
            state = rpc(client, "incident_intelligence_state");
            assert state["proposals"] == [] and state["runs"] == [] and state["decisions"] == [];
            assert rpc(client, "clear_demo")["reports_removed"] == 0;
            rpc(client, "load_demo");
            assert len(rpc(client, "all_reports")) == 16;
            assert not ({item["id"] for item in before} & {item["id"] for item in rpc(client, "all_reports")});
        } finally { client.close(); }
    }
}

test "cleanup preserves genuine reports and mixed analysis run history" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            assert client.register_user("citizen", secrets.token_urlsafe(24)).ok;
            genuine = rpc(client, "create_report", real_draft());
            authority(client); rpc(client, "load_demo");
            run = rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24), "mode": "demo_mock"});
            assert run["reports_examined"] == 17 and run["proposals_created"] == 4;
            cleared = rpc(client, "clear_demo");
            assert cleared["reports_removed"] == 16;
            assert cleared["runs_removed"] == 0 and cleared["runs_preserved"] == 1;
            assert public_data(rpc(client, "all_reports")) == public_data([genuine]);
            assert rpc(client, "incident_intelligence_state")["runs"][0]["id"] == run["id"];
        } finally { client.close(); }
    }
}

test "mixed genuine demo proposals block cleanup without partial deletions" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("intelligence_test_app.jac", base_path=directory);
        try {
            assert client.register_user("citizen", secrets.token_urlsafe(24)).ok;
            rpc(client, "create_report", real_draft(True));
            authority(client); rpc(client, "load_demo");
            rpc(client, "fixture_analysis", {"request_id": secrets.token_urlsafe(24), "mode": "demo_mock"});
            before = rpc(client, "all_reports"); state = rpc(client, "incident_intelligence_state");
            assert len([item for item in state["proposals"] if len(item["report_ids"]) == 5]) == 1;
            assert not client.post("/function/clear_demo", json={}).ok;
            assert public_data(rpc(client, "all_reports")) == public_data(before);
            assert len(rpc(client, "incident_intelligence_state")["proposals"]) == 4;
        } finally { client.close(); }
    }
}

test "second authority cannot clear another authority owned dataset" {
    with DemoEnvironment(), tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            owner = authority(client); rpc(client, "load_demo");
            authority(client, "second_authority");
            assert rpc(client, "demo_dataset_status")["report_count"] == 16;
            assert not rpc(client, "demo_dataset_status")["can_clear"];
            assert rpc(client, "load_demo")["message"] == "Demo dataset already loaded.";
            assert not client.post("/function/clear_demo", json={}).ok;
            client.set_auth_token(owner);
            assert rpc(client, "clear_demo")["reports_removed"] == 16;
        } finally { client.close(); }
    }
}
