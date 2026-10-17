"""Canonical client-safe cleanup planning input, output and latest-result contracts."""
obj CleanupResponseState {
    has organization_id: str, organization_name: str, role: str, status: str;
}
obj CleanupPlanningContext {
    has event_id: str, incident_id: str, event_revision: int, event_status: str,
        title: str, description: str, location_text: str, scheduled_at: str, observed_at: str,
        required_volunteers: int, joined_volunteers: int, remaining_volunteers: int,
        incident_category: str, incident_severity: str, lead_organization_id: str,
        lead_organization_name: str, response_state: list[CleanupResponseState];
}
obj CleanupAssessment {
    has risk_level: str, shortage_detected: bool, volunteers_missing: int,
        recommendation_type: str, reasoning_summary: str, recommended_actions: list[str],
        support_organization_ids: list[str];
}
obj CleanupPlanningView {
    has run_id: str, event_id: str, status: str, input_state: CleanupPlanningContext,
        assessment: CleanupAssessment | None, created_at: str, completed_at: str,
        error_category: str, error_summary: str, stale: bool;
}
