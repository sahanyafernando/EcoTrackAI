"""Bounded orchestration contracts; no model-selected tools or credentials."""
import from contracts.cleanup_ai_views { CleanupPlanningContext }
obj CoordinatorContext {
    has event_type: str, entity_id: str, incident_id: str, incident_category: str,
        incident_severity: str, existing_lead_id: str,
        cleanup: CleanupPlanningContext | None = None;
}
obj CoordinatorDecision {
    has action: str, target_agent: str, reason_summary: str, entity_id: str;
}
