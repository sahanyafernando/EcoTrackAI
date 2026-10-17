"""Confirmed-incident response policy. Authority assigns; verified members read."""
import from uuid { uuid5, NAMESPACE_URL }
import from jaclang { JacRuntime as Jac }
import from core.domain { Organization, OrganizationIndex, own_organization, require_authenticated,
    require_capability, is_authority, can_read_responses, now }
import from core.incidents { Incident, IncidentIndex }
import from agents.incident_intelligence { analysis_lock }
import from contracts.response_views { VerifiedOrganizationView, ResponseView, ResponseAssessment,
    ResponseRecommendationView, ResponseIncidentView, ResponseBoardView }

node IncidentResponse {
    has incident_id: str, organization_id: str, organization_name: str, role: str,
        created_at: str, updated_at: str, assigned_at: str, assigned_by: str,
        status: str = "active", revision: int = 1;
    def __jac_access__ -> AccessLevel {
        if can_read_responses() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
node ResponseRecommendation {
    has incident_id: str, run_id: str, lead_organization_id: str,
        support_organization_ids: list[str], reasoning_summary: str, created_at: str;
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
edge ResponseIndex: any --> any {
    def __jac_access__ -> AccessLevel {
        if can_read_responses() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
def find_confirmed_incident(incident_id: str) -> Incident {
    require_capability("response:read");
    for item in [root.shared ->:IncidentIndex:-> [?:Incident]] {
        if jid(item) == incident_id and item.status == "confirmed" { return item; }
    }
    raise ValueError("Confirmed Incident not found.");
}
def verified_organizations() -> list[VerifiedOrganizationView] {
    require_capability("agent:coordinate_response");
    return [VerifiedOrganizationView(id=jid(item), name=item.name, description=item.description)
        for item in [root.shared ->:OrganizationIndex:-> [?:Organization]] if item.verification_status == "verified"];
}
def active_responses(incident_id: str) -> list[IncidentResponse] {
    require_capability("response:read");
    return [item for item in [root.shared ->:ResponseIndex:-> [?:IncidentResponse]]
        if item.incident_id == incident_id and item.status == "active"];
}
def check_existing_lead(incident_id: str) -> IncidentResponse | None {
    find_confirmed_incident(incident_id);
    for item in active_responses(incident_id) {
        if item.role == "lead" { return item; }
    }
    return None;
}
def response_view(item: IncidentResponse) -> ResponseView {
    return ResponseView(response_id=jid(item), incident_id=item.incident_id,
        organization_id=item.organization_id, organization_name=item.organization_name,
        role=item.role, status=item.status, created_at=item.created_at, updated_at=item.updated_at,
        assigned_at=item.assigned_at, assigned_by=item.assigned_by, revision=item.revision);
}
def response_board() -> ResponseBoardView {
    require_authenticated();
    org = own_organization();
    status = org.verification_status if org is not None else "";
    if not is_authority() and org is not None and status != "verified" {
        return ResponseBoardView(incidents=[], organizations=[], authority=False, organization_status=status);
    }
    require_capability("response:read");
    authority = is_authority();
    incidents: list[ResponseIncidentView] = [];
    for item in [root.shared ->:IncidentIndex:-> [?:Incident, -confirmed_at]] {
        if item.status != "confirmed" { continue; }
        responses = active_responses(jid(item));
        lead = check_existing_lead(jid(item));
        own_role = "Unassigned";
        for response in responses {
            if org is not None and response.organization_id == jid(org) { own_role = response.role; }
        }
        recommendations: list[ResponseRecommendationView] = [];
        if authority {
            recommendations = [ResponseRecommendationView(run_id=value.run_id,
                lead_organization_id=value.lead_organization_id, support_organization_ids=value.support_organization_ids,
                reasoning_summary=value.reasoning_summary, created_at=value.created_at)
                for value in [root.shared ->:ResponseIndex:-> [?:ResponseRecommendation, -created_at]]
                if value.incident_id == jid(item)][:1];
        }
        incidents.append(ResponseIncidentView(incident_id=jid(item), category=item.category,
            severity=item.severity, status=item.status, report_count=len(item.report_ids), revision=item.revision,
            lead=response_view(lead) if lead is not None else None,
            supports=[response_view(value) for value in responses if value.role == "support"],
            own_role=own_role, recommendations=recommendations));
    }
    return ResponseBoardView(incidents=incidents,
        organizations=verified_organizations() if authority else [], authority=authority, organization_status=status);
}
def validate_response_assessment(value: ResponseAssessment, eligible: list[VerifiedOrganizationView],
                                 existing_lead: str, assigned: list[str]) -> None {
    if not isinstance(value, ResponseAssessment) { raise ValueError("Invalid response recommendation."); }
    ids = [item.id for item in eligible];
    selected = ([value.lead_organization_id] if value.lead_organization_id else []) + value.support_organization_ids;
    if (len(selected) != len(set(selected)) or len(selected) > 10
        or any([id not in ids or id in assigned for id in selected])
        or (existing_lead != "" and value.lead_organization_id != "")
        or not value.reasoning_summary.strip() or len(value.reasoning_summary) > 1500) {
        raise ValueError("Recommendation violates eligibility or existing response ownership.");
    }
}
def assign_response(incident_id: str, organization_id: str, role: str,
                    expected_revision: int, run_id: str) -> ResponseView {
    require_capability("response:assign");
    if role not in ["lead", "support"] { raise ValueError("Choose lead or support."); }
    if not analysis_lock.acquire(blocking=False) { raise ValueError("An agent or maintenance is running. Retry shortly."); }
    try {
        Jac.commit(); Jac.get_context().mem.read_barrier();
        incident = find_confirmed_incident(incident_id);
        if incident.revision != expected_revision { raise ValueError("Incident response changed. Refresh before assigning."); }
        eligible = verified_organizations();
        names = {item.id: item.name for item in eligible};
        if organization_id not in names { raise PermissionError("Only a currently VERIFIED organization can respond."); }
        if any([item.organization_id == organization_id for item in active_responses(incident_id)]) {
            raise ValueError("This organization already has an active response.");
        }
        if role == "lead" and check_existing_lead(incident_id) is not None {
            raise ValueError("Lead organization already assigned. Join as Support.");
        }
        allowed = False;
        for recommendation in [root.shared ->:ResponseIndex:-> [?:ResponseRecommendation]] {
            if recommendation.run_id == run_id and recommendation.incident_id == incident_id {
                allowed = (recommendation.lead_organization_id == organization_id if role == "lead"
                    else organization_id in recommendation.support_organization_ids);
            }
        }
        if not allowed { raise PermissionError("An authorized recommendation for this Incident and role is required."); }
        stamp = now();
        # All assignments touch the same persisted Incident revision. Native write
        # conflicts plus the lead check serialize competing requests across accounts.
        incident.revision += 1; incident.updated_at = stamp;
        response = IncidentResponse(incident_id=incident_id, organization_id=organization_id,
            organization_name=names[organization_id], role=role, created_at=stamp,
            updated_at=stamp, assigned_at=stamp, assigned_by=jid(root));
        response.__jac__.id = uuid5(NAMESPACE_URL, "ecotrack:response:" + incident_id + ":" + organization_id);
        root ++> response; root.shared +>:ResponseIndex:+> response;
        Jac.commit();
        return response_view(response);
    } finally { analysis_lock.release(); }
}
