"""Offline assessors reachable only from the isolated test application."""
import from jaclang { JacRuntime as Jac }
import from jaclang.byllm.lib { MockLLM }
import from core.cleanups { find_event }
import from core.intelligence { RunView }
import from contracts.cleanup_ai_views { CleanupPlanningContext, CleanupAssessment }
import from agents.cleanup_volunteer { run_cleanup_planning, assess_cleanup }

def:protect fixture_cleanup_ai(event_id: str, request_id: str, mode: str = "positive") -> RunView {
    def assessor(context: CleanupPlanningContext) -> CleanupAssessment {
        if mode == "failure" { raise RuntimeError("Private provider secret must never be stored"); }
        if mode == "timeout" { raise TimeoutError("Private timeout details"); }
        if mode == "assert_three" {
            assert context.required_volunteers == 8;
            assert context.joined_volunteers == 3 and context.remaining_volunteers == 5;
        }
        supports = [item.organization_id for item in context.response_state if item.role == "support" and item.status == "active"];
        shortage = context.remaining_volunteers > 0;
        output = {"risk_level": "high" if shortage else "low", "shortage_detected": shortage,
            "volunteers_missing": context.remaining_volunteers,
            "recommendation_type": ("combined_recovery" if supports else "recruit_volunteers") if shortage else "sufficient_capacity",
            "reasoning_summary": "Offline semantic assessment recommends a proportionate response to the supplied capacity and Incident context.",
            "recommended_actions": ["Recruit " + str(context.remaining_volunteers) + " additional volunteers.", "Ask assigned Support organizations for assistance."] if shortage else ["Maintain confirmed capacity and review attendance before the event."],
            "support_organization_ids": supports if shortage else []};
        if mode == "wrong_missing" { output["volunteers_missing"] = context.remaining_volunteers + 1; }
        if mode == "unknown_support" { output["support_organization_ids"] = ["nonexistent-organization"]; }
        if mode == "lead_as_support" { output["support_organization_ids"] = [context.lead_organization_id]; }
        if mode == "duplicate_support" { output["support_organization_ids"] = supports + supports; }
        if mode == "invalid_risk" { output["risk_level"] = "impossible"; }
        if mode == "invalid_type" { output["recommendation_type"] = "assign_new_lead"; }
        if mode == "wrong_shortage" { output["shortage_detected"] = not shortage; }
        if mode == "stale_event" {
            # Simulate a concurrent human state change; the production model has no
            # mutation tool. The post-call fresh read must refuse this assessment.
            event = find_event(context.event_id); event.status = "cancelled"; event.revision += 1;
            Jac.commit();
        }
        llm = MockLLM(outputs=[output]);
        result = assess_cleanup(context, llm);
        assert len(llm.seen) == 1 and llm.exhausted();
        return result;
    }
    return run_cleanup_planning(event_id, request_id, assessor);
}
