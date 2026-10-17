test "Haversine meters identity symmetry known distance and dateline" {
    first = observation("a", 0.0, 0.0);
    second = observation("b", 0.0, 1.0);
    assert calculate_report_distance(first, first) == 0;
    assert abs(calculate_report_distance(first, second) - 111195.08) < 1;
    assert abs(calculate_report_distance(first, second) - calculate_report_distance(second, first)) < 0.001;
    assert calculate_report_distance(observation("c", 0.0, 179.999), observation("d", 0.0, -179.999)) < 250;
}

test "candidate filters distance time category status and identity" {
    config = IntelligenceConfig(); first = observation("a");
    assert candidate_signal(first, observation("b", 6.9274), config) is not None;
    assert candidate_signal(first, observation("far", 7.0), config) is None;
    assert candidate_signal(first, observation("old", stamp="2026-10-13T23:59:59+00:00"), config) is None;
    assert candidate_signal(first, observation("boundary", stamp="2026-10-14T00:00:00+00:00"), config) is not None;
    assert candidate_signal(first, observation("category", category="blocked_drain"), config) is None;
    assert candidate_signal(first, observation("compatible", category="overflowing_waste"), config) is not None;
    assert candidate_signal(first, observation("status", status="linked_to_incident"), config) is None;
    assert candidate_signal(first, first, config) is None;
}

test "category equality alone is insufficient and lexical overlap is deterministic" {
    config = IntelligenceConfig(); first = observation("a");
    unrelated = observation("b", description="A loud vehicle stopped at the market.",
        location_text="Siyambala bus halt");
    assert candidate_signal(first, unrelated, config) is None;
    matching = observation("c", description="Rubbish beside the canal footbridge.", location_text="Bridge");
    signal = candidate_signal(first, matching, config);
    assert signal is not None;
    assert "bridge" in signal.location_overlap_words;
    assert signal.compatibility_score >= config.min_candidate_score;
}

test "related categories can group with location lexical and geographic evidence" {
    config = IntelligenceConfig();
    first = observation("drain", category="blocked_drain",
        description="Floodwater around the Araliya junction drain.", location_text="Araliya junction drain");
    second = observation("unrelated", category="overflowing_waste", latitude=6.9272,
        description="Market bins overflowing beside the bus stop.", location_text="Siyambala bus stop");
    assert candidate_signal(first, second, config) is None;
    related = observation("related", category="overflowing_waste",
        description="Rainwater blocked by debris in the Araliya junction drain.",
        location_text="Araliya junction drain");
    signal = candidate_signal(first, related, config);
    assert signal is not None;
    assert signal.category_relation == "related";
}

test "MockLLM parses a typed batch of assessments" {
    import from jaclang.byllm.lib { MockLLM }
    import from agents.incident_intelligence { assess_candidates }
    import from core.intelligence { CandidateGroup }
    group = CandidateGroup(candidate_group_id="group-a",
        reports=[observation("a"), observation("b", 6.9272)], signals=[]);
    assessment = {"candidate_group_id": "group-a", "same_incident": True,
        "confidence": 0.9, "reasoning_summary": "The observations share a location.",
        "matching_signals": ["Shared location"], "conflicting_signals": [],
        "suggested_category": "illegal_dumping", "suggested_severity": "medium"};
    llm = MockLLM(outputs=[[assessment]]);
    result = assess_candidates([group], llm);
    assert len(result) == 1 and result[0].candidate_group_id == "group-a";
}

test "complete link grouping excludes long chains and duplicate inputs and stays bounded" {
    config = IntelligenceConfig(max_reports=20, max_groups=2, max_group_size=3);
    items = [observation("a", 0.0, 0.0), observation("b", 0.0, 0.002), observation("c", 0.0, 0.004)];
    groups = find_candidate_reports(items + items, config);
    assert len(groups) == 1;
    assert len(groups[0].reports) == 2;
    for group in groups {
        assert len(group.reports) == len({item.id for item in group.reports});
        for first in group.reports {
            for second in group.reports {
                if first.id != second.id { assert candidate_signal(first, second, config) is not None; }
            }
        }
    }
    assert find_candidate_reports([], config) == [];
    assert len(find_candidate_reports([observation(str(i)) for i in range(30)], config)) <= 2;
}

test "positive semantics persist canonical proposal and leave all reports unchanged" { lifecycle("positive", "completed", 1); }
test "negative semantics produce no proposal" { lifecycle("negative", "completed", 0); }
test "confidence below threshold produces no proposal" { lifecycle("low", "completed", 0); }
test "model failure is recorded without leaking provider details" { lifecycle("failure", "failed", 0); }
test "malformed model confidence fails safely" { lifecycle("malformed", "failed", 0); }
test "unknown assessment group rejects the batch before proposals" { lifecycle("unknown_group", "failed", 0); }
test "missing assessment rejects the batch before proposals" { lifecycle("missing_assessment", "failed", 0); }
test "duplicate assessment rejects the batch before proposals" { lifecycle("duplicate_assessment", "failed", 0); }
test "stale report snapshots cannot become proposals" { lifecycle("stale", "failed", 0); }
test "duplicate report IDs cannot become proposals" { lifecycle("duplicate_ids", "failed", 0); }
test "missing report references cannot become proposals" { lifecycle("missing", "failed", 0); }
test "native byLLM batch structured output creates proposals offline" { lifecycle("mock_byllm", "completed", 1); }

test "authority only triggers analysis and reads agent data" {
    previous = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS", "");
    os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = "";
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        password = secrets.token_urlsafe(24);
        try {
            body = {"request_id": secrets.token_urlsafe(24)};
            for endpoint in ["run_incident_intelligence", "incident_intelligence_state"] {
                assert client.post("/function/" + endpoint, json=body).status_code == 401;
            }
            assert client.register_user("citizen", password).ok;
            for endpoint in ["run_incident_intelligence", "incident_intelligence_state"] {
                assert not client.post("/function/" + endpoint, json=body).ok;
            }
            application = rpc(client, "apply", {"name": "Response group", "description": "Local environment"});
            org_token = client._auth_token or "";
            assert not client.post("/function/run_incident_intelligence", json=body).ok;
            assert client.register_user("authority", password).ok;
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = rpc(client, "account")["root_id"];
            assert "agent:run_intelligence" in rpc(client, "account")["capabilities"];
            empty = rpc(client, "run_incident_intelligence", body);
            assert empty["status"] == "completed";
            assert empty["reports_examined"] == 0;
            assert empty["candidate_groups_examined"] == 0;
            rpc(client, "review", {"organization_id": application["id"], "decision": "verified", "expected_revision": 1});
            client.set_auth_token(org_token);
            assert not client.post("/function/run_incident_intelligence", json=body | {"context": "authority", "capabilities": ["agent:run_intelligence"]}).ok;
            assert not client.post("/function/incident_intelligence_state", json={}).ok;
            assert "agent:run_intelligence" not in rpc(client, "account")["capabilities"];
            # Injection is internal only; there are no mock or proposal-writing RPCs.
            for endpoint in ["fixture_analysis", "create_cluster_proposal", "assess_candidates"] {
                assert endpoint not in client.server.get_functions();
                assert not client.post("/function/" + endpoint, json=body).ok;
            }
        } finally { client.close(); os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = previous; }
    }
}

test "configuration validation and custom thresholds" {
    names = ["ECOTRACK_DUPLICATE_RADIUS_METERS", "ECOTRACK_DUPLICATE_TIME_WINDOW_HOURS",
        "ECOTRACK_DUPLICATE_LOCATION_OVERLAP", "ECOTRACK_DUPLICATE_DESCRIPTION_OVERLAP",
        "ECOTRACK_DUPLICATE_MIN_SCORE", "ECOTRACK_CLUSTER_CONFIDENCE_THRESHOLD"];
    previous = {name: os.environ.get(name) for name in names};
    try {
        for name in names { os.environ.pop(name, None); }
        os.environ[names[0]] = "100";
        assert intelligence_config().radius_meters == 100;
        os.environ[names[0]] = "250";
        os.environ[names[5]] = "0.95";
        lifecycle("positive", "completed", 0);
        for (name, invalid) in [(names[0], "nan"), (names[0], "0"), (names[1], "-1"),
            (names[2], "1.1"), (names[3], "-0.1"), (names[4], "2"), (names[5], "1.1")] {
            os.environ[name] = invalid;
            with testraises(ValueError) { intelligence_config(); }
            os.environ[name] = "250" if name == names[0] else (
                "72" if name == names[1] else ("0.25" if name in [names[2], names[3]]
                    else ("0.5" if name == names[4] else "0.7")));
        }
    } finally {
        for name in names {
            if previous[name] is None { os.environ.pop(name, None); }
            else { os.environ[name] = previous[name] or ""; }
        }
    }
}

test "missing model configuration produces a failed run while reports stay available" {
    previous_model = os.environ.get("BYLLM_DEFAULT_MODEL");
    previous_authority = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS", "");
    os.environ["BYLLM_DEFAULT_MODEL"] = "";
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            assert client.register_user("citizen", secrets.token_urlsafe(24)).ok;
            first = rpc(client, "create_report", draft());
            rpc(client, "create_report", draft() | {"latitude": 6.9274});
            assert client.register_user("authority", secrets.token_urlsafe(24)).ok;
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = rpc(client, "account")["root_id"];
            run = rpc(client, "run_incident_intelligence", {"request_id": secrets.token_urlsafe(24)});
            assert run["status"] == "failed";
            assert "Set BYLLM_DEFAULT_MODEL" in run["error_summary"];
            assert len(rpc(client, "incident_intelligence_state")["proposals"]) == 0;
            assert len(rpc(client, "all_reports")) == 2;
            assert rpc(client, "get_report", {"report_id": first["id"]})["status"] == "submitted";
        } finally {
            client.close();
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = previous_authority;
            if previous_model is None { os.environ.pop("BYLLM_DEFAULT_MODEL", None); }
            else { os.environ["BYLLM_DEFAULT_MODEL"] = previous_model; }
        }
    }
}

test "single eligible report completes without a provider call" {
    previous = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS", "");
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            assert client.register_user("authority", secrets.token_urlsafe(24)).ok;
            os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = rpc(client, "account")["root_id"];
            rpc(client, "create_report", draft());
            run = rpc(client, "run_incident_intelligence", {"request_id": secrets.token_urlsafe(24)});
            assert run["status"] == "completed";
            assert run["reports_examined"] == 1;
            assert run["candidate_groups_examined"] == 0;
            assert run["proposals_created"] == 0;
        } finally { client.close(); os.environ["ECOTRACK_AUTHORITY_ROOT_IDS"] = previous; }
    }
}
