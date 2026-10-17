"""Canonical client-safe response coordination contracts."""
obj VerifiedOrganizationView {
    has id: str, name: str, description: str;
}
obj ResponseView {
    has response_id: str, incident_id: str, organization_id: str, organization_name: str,
        role: str, status: str, created_at: str, updated_at: str, assigned_at: str,
        assigned_by: str, revision: int;
}
obj ResponseAssessment {
    has lead_organization_id: str, support_organization_ids: list[str], reasoning_summary: str;
}
obj ResponseRecommendationView {
    has run_id: str, lead_organization_id: str, support_organization_ids: list[str],
        reasoning_summary: str, created_at: str;
}
obj ResponseIncidentView {
    has incident_id: str, category: str, severity: str, status: str, report_count: int,
        revision: int, lead: ResponseView | None, supports: list[ResponseView], own_role: str,
        recommendations: list[ResponseRecommendationView];
}
obj ResponseBoardView {
    has incidents: list[ResponseIncidentView], organizations: list[VerifiedOrganizationView],
        authority: bool, organization_status: str;
}
obj ResponseContext {
    has incident_id: str, category: str, severity: str, observation_summaries: list[str],
        existing_lead_id: str, assigned_organization_ids: list[str],
        organizations: list[VerifiedOrganizationView];
}
