"""Client-safe incident and explicit human-review contracts."""
obj IncidentView {
    has incident_id: str, category: str, severity: str, status: str,
        report_ids: list[str], created_at: str, updated_at: str,
        confirmed_at: str, confirmed_by: str, source_proposal_id: str, revision: int;
}
obj HumanReviewView {
    has proposal_id: str, reviewer: str, timestamp: str, previous_status: str,
        resulting_status: str, proposal_revision: int, incident_id: str;
}
