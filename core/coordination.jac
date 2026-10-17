"""Trusted observation and bounded routing policy. Never performs operational mutations."""
import from contracts.coordinator_views { CoordinatorContext, CoordinatorDecision }
import from core.domain { require_capability }
import from core.responses { find_confirmed_incident, check_existing_lead }
import from core.cleanup_planning { collect_cleanup_context, cleanup_context_signature }

def coordinator_context(event_type: str, entity_id: str) -> CoordinatorContext {
    require_capability("agent:coordinate");
    if event_type not in ["incident_confirmed", "cleanup_created", "volunteer_state_changed"] {
        raise ValueError("Unsupported Coordinator event.");
    }
    if event_type == "incident_confirmed" {
        incident = find_confirmed_incident(entity_id);
        lead = check_existing_lead(entity_id);
        return CoordinatorContext(event_type=event_type, entity_id=entity_id, incident_id=entity_id,
            incident_category=incident.category, incident_severity=incident.severity,
            existing_lead_id=lead.organization_id if lead is not None else "");
    }
    cleanup = collect_cleanup_context(entity_id);
    return CoordinatorContext(event_type=event_type, entity_id=entity_id, incident_id=cleanup.incident_id,
        incident_category=cleanup.incident_category, incident_severity=cleanup.incident_severity,
        existing_lead_id=cleanup.lead_organization_id, cleanup=cleanup);
}
def coordinator_signature(context: CoordinatorContext) -> tuple[any, ...] {
    return (context.event_type, context.entity_id, context.incident_id, context.incident_category,
        context.incident_severity, context.existing_lead_id,
        cleanup_context_signature(context.cleanup) if context.cleanup is not None else ());
}
def validate_coordinator_decision(value: CoordinatorDecision, context: CoordinatorContext) -> None {
    if (not isinstance(value, CoordinatorDecision) or value.entity_id != context.entity_id
        or not value.reason_summary.strip() or len(value.reason_summary) > 1500) {
        raise ValueError("Invalid Coordinator decision or entity reference.");
    }
    allowed = {"run_response_coordination": "response_coordination",
        "run_cleanup_volunteer": "cleanup_volunteer", "no_action": "none", "require_human_review": "none"};
    if value.action not in allowed or value.target_agent != allowed[value.action] {
        raise ValueError("Unsupported Coordinator action/target pair.");
    }
    if value.action == "run_response_coordination" and (context.event_type != "incident_confirmed" or context.existing_lead_id) {
        raise ValueError("Response routing requires a confirmed Incident without an active Lead.");
    }
    if value.action == "run_cleanup_volunteer" and (context.cleanup is None or context.cleanup.event_status not in ["planned", "active"]) {
        raise ValueError("Cleanup routing requires an open official event.");
    }
}
