test "citizen gets citizen navigation" {
    context = workspace_context(["report:create", "report:read_own"], False);
    assert context == "citizen";
    assert [item.label for item in workspace_navigation(context)] == [
        "Overview", "Report Issue", "My Reports", "Cleanup Events", "Profile"
    ];
}

test "organization membership selects organization workspace" {
    context = workspace_context(["organization:apply"], True);
    assert context == "organization";
    assert [item.label for item in workspace_navigation(context)] == [
        "Overview", "Organization", "Incidents", "Cleanup Events", "Volunteers"
    ];
    assert workspace_context(["organization:verified_member"], True) == "organization";
    assert resolve_page(context, "report_issue") == "report_issue";
    assert resolve_page(context, "my_reports") == "my_reports";
}

test "authority takes precedence over organization membership" {
    context = workspace_context(["organization:verify", "report:read_all"], True);
    assert context == "authority";
    assert [item.label for item in workspace_navigation(context)] == [
        "Authority Overview", "Incoming Reports", "Organization Review",
        "Incident Review", "Agent Activity", "Audit"
    ];
}

test "unavailable pages do not turn citizens into authorities" {
    capabilities = ["report:create", "report:read_own"];
    context = workspace_context(capabilities, False);
    for page in ["review", "incoming", "incident_review", "agents", "audit", "invented"] {
        assert resolve_page(context, page) == "overview";
    }
    assert capabilities == ["report:create", "report:read_own"];
    assert workspace_context(capabilities, False) == "citizen";
    assert resolve_page(context, "organization") == "organization";
}
