"""MockLLM wiring exists only in the isolated test entry point."""
import from jaclang.byllm.lib { MockLLM }
import from contracts.coordinator_views { CoordinatorContext, CoordinatorDecision }
import from contracts.cleanup_ai_views { CleanupPlanningContext, CleanupAssessment }
import from contracts.response_views { ResponseContext, ResponseAssessment }
import from agents.coordinator { run_coordinator, assess_coordinator }
import from agents.cleanup_volunteer { assess_cleanup }
import from agents.response_coordination { assess_response }
import from core.intelligence { RunView }

def:protect fixture_coordinator(event_type: str, entity_id: str, request_id: str, mode: str = "positive") -> RunView {
    def route(context: CoordinatorContext) -> CoordinatorDecision {
        if mode == "failure" { raise RuntimeError("Private provider secret"); }
        if mode == "timeout" { raise TimeoutError("Private provider timeout"); }
        action = "run_cleanup_volunteer" if context.cleanup is not None else ("run_response_coordination" if not context.existing_lead_id else "no_action");
        target = "cleanup_volunteer" if context.cleanup is not None else ("response_coordination" if not context.existing_lead_id else "none");
        if mode == "invalid_target" { target = "arbitrary_tool"; }
        if mode == "invalid_action" { action = "confirm_incident"; }
        if mode == "second_lead" { action = "run_response_coordination"; target = "response_coordination"; }
        if mode == "human_review" { action = "require_human_review"; target = "none"; }
        llm = MockLLM(outputs=[{"action": action, "target_agent": target,
            "reason_summary": "Route the trusted current state to the bounded specialist.", "entity_id": "forged" if mode == "wrong_entity" else context.entity_id}]);
        result = assess_coordinator(context, llm);
        assert len(llm.seen) == 1 and llm.exhausted();
        return result;
    }
    def cleanup(context: CleanupPlanningContext) -> CleanupAssessment {
        if mode == "specialist_failure" { raise RuntimeError("Private specialist error"); }
        supports = [item.organization_id for item in context.response_state if item.role == "support"];
        llm = MockLLM(outputs=[{"risk_level": "high", "shortage_detected": context.remaining_volunteers > 0,
            "volunteers_missing": context.remaining_volunteers,
            "recommendation_type": "recruit_volunteers" if context.remaining_volunteers > 0 else "sufficient_capacity",
            "reasoning_summary": "Current capacity calls for a proportionate planning response.",
            "recommended_actions": ["Review current capacity with the assigned Lead."], "support_organization_ids": supports}]);
        result = assess_cleanup(context, llm);
        assert len(llm.seen) == 1 and llm.exhausted();
        return result;
    }
    def response(context: ResponseContext) -> ResponseAssessment {
        if mode == "specialist_failure" { raise RuntimeError("Private specialist error"); }
        llm = MockLLM(outputs=[{"lead_organization_id": context.organizations[0].id if not context.existing_lead_id else "",
            "support_organization_ids": [], "reasoning_summary": "Supplied verified organization fits the Incident category."}]);
        result = assess_response(context, llm);
        assert len(llm.seen) == 1 and llm.exhausted();
        return result;
    }
    return run_coordinator(event_type, entity_id, request_id, route, cleanup, response);
}
