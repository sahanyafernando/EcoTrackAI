"""Authenticated RPC boundary. All policy and mutations live in Jac core."""
import from contracts.report_views { ReportView }
import from core.domain {
    AccountView, OrganizationView, Organization, OrganizationIndex,
    ensure_profile, own_organization, capabilities, org_view,
    require_capability, apply_organization, edit_application, review_application
}

def:protect account(display_name: str = "") -> AccountView {
    profile = ensure_profile(display_name);
    org = own_organization();
    return AccountView(display_name=profile.display_name,
        account_status=profile.account_status, volunteer_enabled=profile.volunteer_enabled,
        created_at=profile.created_at, updated_at=profile.updated_at, revision=profile.revision,
        root_id=jid(root), capabilities=capabilities(),
        organization=org_view(org) if org is not None else None);
}

def:protect apply(name: str, description: str) -> OrganizationView {
    return apply_organization(name, description);
}

def:protect edit_organization(organization_id: str, name: str, description: str,
                              expected_revision: int) -> OrganizationView {
    return edit_application(organization_id, name, description, expected_revision);
}

def:protect organizations() -> list[OrganizationView] {
    require_capability("audit:read");
    return [org_view(org) for org in [root.shared ->:OrganizationIndex:->][?:Organization]];
}

def:protect review(organization_id: str, decision: str, expected_revision: int) -> OrganizationView {
    return review_application(organization_id, decision, expected_revision);
}


import from core.reports {
    REPORT_CATEGORIES, submit_report, own_reports, incoming_reports, inspect_report
}

def:protect report_categories() -> list[str] {
    require_capability("report:create");
    return list(REPORT_CATEGORIES);
}

def:protect create_report(description: str, category: str, latitude: float, longitude: float,
                          submission_id: str, location_text: str = "") -> ReportView {
    return submit_report(description, category, latitude, longitude, location_text, submission_id);
}

def:protect my_reports() -> list[ReportView] { return own_reports(); }

def:protect all_reports() -> list[ReportView] { return incoming_reports(); }

def:protect get_report(report_id: str) -> ReportView { return inspect_report(report_id); }

import from core.intelligence { IntelligenceView, RunView, intelligence_state }
import from agents.incident_intelligence { run_intelligence }

def:protect incident_intelligence_state() -> IntelligenceView { return intelligence_state(); }

def:protect run_incident_intelligence(request_id: str) -> RunView {
    return run_intelligence(request_id);
}

import from core.demo_dataset { DemoState, DemoResult, demo_state, load_demo_dataset, clear_demo_dataset }

def:protect demo_dataset_status() -> DemoState { return demo_state(); }
def:protect load_demo() -> DemoResult { return load_demo_dataset(); }
def:protect clear_demo() -> DemoResult { return clear_demo_dataset(); }

import from contracts.incident_views { IncidentView, HumanReviewView }
import from core.incidents { list_confirmed_incidents, list_human_reviews, review_cluster_proposal }

def:protect confirmed_incidents() -> list[IncidentView] { return list_confirmed_incidents(); }
def:protect incident_human_reviews() -> list[HumanReviewView] { return list_human_reviews(); }
def:protect review_cluster(proposal_id: str, decision: str, expected_revision: int) -> HumanReviewView {
    return review_cluster_proposal(proposal_id, decision, expected_revision);
}

import from contracts.response_views { ResponseBoardView, ResponseView }
import from core.responses { response_board, assign_response }
import from agents.response_coordination { run_response_coordination }
def:protect incident_response_board() -> ResponseBoardView { return response_board(); }
def:protect coordinate_response(incident_id: str, request_id: str) -> RunView {
    return run_response_coordination(incident_id, request_id);
}
def:protect accept_response(incident_id: str, organization_id: str, role: str,
                           expected_revision: int, run_id: str) -> ResponseView {
    return assign_response(incident_id, organization_id, role, expected_revision, run_id);
}
