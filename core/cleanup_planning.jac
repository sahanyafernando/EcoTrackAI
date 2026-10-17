"""Deterministic cleanup planning tools and validation. No model-side mutations."""
import from core.domain { require_capability, is_authority, now }
import from core.cleanups { find_event, manages_incident, get_event_capacity_state }
import from core.responses { find_confirmed_incident, check_existing_lead, active_responses }
import from core.intelligence { AgentRun, IntelligenceIndex }
import from contracts.cleanup_ai_views { CleanupPlanningContext, CleanupResponseState, CleanupAssessment, CleanupPlanningView }

glob CLEANUP_RISK_LEVELS: list[str] = ["low", "medium", "high", "critical"];
glob CLEANUP_RECOMMENDATIONS: list[str] = ["sufficient_capacity", "recruit_volunteers",
    "request_support", "reschedule_consideration", "combined_recovery"];

def require_cleanup_planner(event_id: str) -> None {
    require_capability("agent:plan_cleanup");
    event = find_event(event_id);
    if not manages_incident(event.incident_id, event.lead_organization_id) {
        raise PermissionError("Only the current active verified Lead may run Cleanup AI.");
    }
}
def collect_cleanup_context(event_id: str) -> CleanupPlanningContext {
    # Authority may inspect deterministic state; execution separately requires Lead.
    event = find_event(event_id);
    if not is_authority() { require_cleanup_planner(event_id); }
    capacity = get_event_capacity_state(event_id);
    incident = find_confirmed_incident(event.incident_id);
    lead = check_existing_lead(event.incident_id);
    if lead is None or lead.organization_id != event.lead_organization_id {
        raise ValueError("The event no longer has its assigned active Lead.");
    }
    return CleanupPlanningContext(event_id=event_id, incident_id=event.incident_id,
        event_revision=event.revision, event_status=event.status, title=event.title,
        description=event.description, location_text=event.location_text, scheduled_at=event.scheduled_at, observed_at=now(),
        required_volunteers=capacity.required, joined_volunteers=capacity.joined, remaining_volunteers=capacity.remaining,
        incident_category=incident.category, incident_severity=incident.severity,
        lead_organization_id=lead.organization_id, lead_organization_name=lead.organization_name,
        response_state=[CleanupResponseState(organization_id=item.organization_id,
            organization_name=item.organization_name, role=item.role, status=item.status)
            for item in active_responses(event.incident_id)]);
}
def cleanup_context_signature(context: CleanupPlanningContext) -> tuple[any, ...] {
    return (context.event_id, context.incident_id, context.event_revision, context.event_status,
        context.title, context.description, context.location_text, context.scheduled_at,
        context.required_volunteers, context.joined_volunteers, context.remaining_volunteers,
        context.incident_category, context.incident_severity, context.lead_organization_id,
        context.lead_organization_name, tuple(sorted([(item.organization_id, item.organization_name,
            item.role, item.status) for item in context.response_state])));
}
def validate_cleanup_assessment(value: CleanupAssessment, context: CleanupPlanningContext) -> None {
    if context.event_status not in ["planned", "active"] { raise ValueError("Closed event cannot be planned."); }
    if (not isinstance(value, CleanupAssessment) or value.risk_level not in CLEANUP_RISK_LEVELS
        or value.recommendation_type not in CLEANUP_RECOMMENDATIONS
        or type(value.shortage_detected) is not bool or type(value.volunteers_missing) is not int
        or value.volunteers_missing != context.remaining_volunteers
        or value.shortage_detected != (context.remaining_volunteers > 0)
        or (value.recommendation_type == "sufficient_capacity") != (context.remaining_volunteers == 0)
        or not value.reasoning_summary.strip() or len(value.reasoning_summary) > 1500) {
        raise ValueError("AI output conflicts with trusted capacity or the structured contract.");
    }
    if not isinstance(value.recommended_actions, list) or not 1 <= len(value.recommended_actions) <= 8 {
        raise ValueError("Return 1–8 concise recommended actions.");
    }
    for action in value.recommended_actions {
        if not isinstance(action, str) or not action.strip() or len(action) > 400 {
            raise ValueError("Invalid recommended action.");
        }
    }
    assigned_supports = {item.organization_id for item in context.response_state
        if item.role == "support" and item.status == "active"};
    refs = value.support_organization_ids;
    if not isinstance(refs, list) or len(refs) != len(set(refs)) or not set(refs) <= assigned_supports {
        raise ValueError("Only real assigned active Support organizations may be referenced.");
    }
    if value.recommendation_type in ["request_support", "combined_recovery"] and not refs {
        raise ValueError("A support recommendation requires an assigned Support reference.");
    }
}
def latest_cleanup_plans() -> list[CleanupPlanningView] {
    require_capability("cleanup:read");
    runs = ([root.shared ->:IntelligenceIndex:-> [?:AgentRun, -started_at]] if is_authority()
        else [root --> [?:AgentRun, -started_at]]);
    seen: set[str] = set();
    result: list[CleanupPlanningView] = [];
    for run in runs {
        if run.agent_name != "Cleanup & Volunteer Agent" or not run.cleanup_event_id or run.cleanup_input is None { continue; }
        if run.cleanup_event_id in seen { continue; }
        try { current = collect_cleanup_context(run.cleanup_event_id); }
        except (ValueError, PermissionError) { continue; }
        seen.add(run.cleanup_event_id);
        result.append(CleanupPlanningView(run_id=jid(run), event_id=run.cleanup_event_id, status=run.status,
            input_state=run.cleanup_input, assessment=run.cleanup_assessment, created_at=run.started_at,
            completed_at=run.completed_at, error_category=run.error_category, error_summary=run.error_summary,
            stale=cleanup_context_signature(current) != cleanup_context_signature(run.cleanup_input)));
    }
    return result;
}
