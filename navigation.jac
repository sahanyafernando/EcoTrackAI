"""Presentation policy only. Server capabilities remain the authorization boundary."""
obj NavItem { has id: str, label: str, icon: str; }

def workspace_context(capabilities: list[str], has_organization: bool) -> str {
    if "organization:verify" in capabilities { return "authority"; }
    if has_organization { return "organization"; }
    return "citizen";
}

def workspace_navigation(context: str) -> list[NavItem] {
    if context == "authority" {
        return [NavItem("overview", "Authority Overview", "overview"),
            NavItem("incoming", "Incoming Reports", "reports"),
            NavItem("review", "Organization Review", "organization"),
            NavItem("incident_review", "Incident Review", "incidents"),
            NavItem("agents", "Agent Activity", "activity"),
            NavItem("audit", "Audit", "audit")];
    }
    if context == "organization" {
        return [NavItem("overview", "Overview", "overview"),
            NavItem("organization", "Organization", "organization"),
            NavItem("incidents", "Incidents", "incidents"),
            NavItem("cleanups", "Cleanup Events", "leaf"),
            NavItem("volunteers", "Volunteers", "people")];
    }
    return [NavItem("overview", "Overview", "overview"),
        NavItem("report_issue", "Report Issue", "pin"),
        NavItem("my_reports", "My Reports", "reports"),
        NavItem("cleanups", "Cleanup Events", "leaf"),
        NavItem("profile", "Profile", "person")];
}

def resolve_page(context: str, requested: str) -> str {
    # Personal tools remain reachable from account controls in every workspace.
    if requested in ["profile", "organization", "report_issue", "my_reports"] { return requested; }
    for item in workspace_navigation(context) {
        if item.id == requested { return requested; }
    }
    return "overview";
}

def page_title(context: str, page: str) -> str {
    for item in workspace_navigation(context) {
        if item.id == page { return item.label; }
    }
    if page == "profile" { return "Profile"; }
    if page == "organization" { return "Organization"; }
    if page == "report_issue" { return "Report Issue"; }
    if page == "my_reports" { return "My Reports"; }
    return "Overview";
}
