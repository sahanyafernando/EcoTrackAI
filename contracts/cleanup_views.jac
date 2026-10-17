"""Canonical client-safe cleanup contracts. No private participant identifiers."""
obj CapacityState {
    has event_id: str, required: int, joined: int, remaining: int;
}
obj CleanupEventView {
    has event_id: str, incident_id: str, lead_organization_id: str, organization_name: str,
        category: str, title: str, description: str, location_text: str, latitude: float,
        longitude: float, scheduled_at: str, required_volunteers: int, status: str,
        created_at: str, updated_at: str, revision: int, joined_volunteers: int,
        remaining_needed: int, my_participation: str, can_manage: bool;
}
obj CleanupLeadOption {
    has incident_id: str, category: str;
}
obj CleanupBoardView {
    has events: list[CleanupEventView], lead_incidents: list[CleanupLeadOption];
}
