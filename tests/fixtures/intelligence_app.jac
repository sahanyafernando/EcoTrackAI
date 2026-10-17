"""Isolated test entry point. Test assessors are unreachable from production main."""
import from endpoints { account, create_report, all_reports, my_reports, get_report, apply,
    review, incident_intelligence_state, run_incident_intelligence }
import from core.intelligence {
    CandidateGroup, ClusterAssessment, RunView, create_cluster_proposal, intelligence_config,
    validate_candidate, AgentRun, IntelligenceIndex
}
import from agents.incident_intelligence { run_intelligence, assess_candidates }
import from jaclang.byllm.lib { MockLLM }
import from agents.response_coordination { run_response_coordination, assess_response }
import from contracts.response_views { ResponseContext, ResponseAssessment }

def:protect fixture_coordination(incident_id: str, request_id: str, mode: str = "positive") -> RunView {
    def assessor(context: ResponseContext) -> ResponseAssessment {
        if mode == "failure" { raise RuntimeError("Private provider failure secret"); }
        lead = context.organizations[0].id if context.existing_lead_id == "" else "";
        if mode == "alternate" { lead = context.organizations[-1].id; }
        supports = [item.id for item in context.organizations if item.id != lead];
        if mode == "duplicate_lead" { lead = context.organizations[0].id; }
        if mode == "unknown" { supports = ["unknown-organization"]; }
        output = {"lead_organization_id": lead, "support_organization_ids": supports,
            "reasoning_summary": "Verified groups fit environmental response; existing assignments were checked."};
        llm = MockLLM(outputs=[output]);
        result = assess_response(context, llm);
        assert len(llm.seen) == 1 and llm.exhausted();
        return result;
    }
    return run_response_coordination(incident_id, request_id, assessor);
}

# Fixture-only modes never enter the application API.
def:protect fixture_analysis(request_id: str, mode: str = "positive") -> RunView {
    def assessor(groups: list[CandidateGroup]) -> list[ClusterAssessment] {
        if mode == "failure" { raise RuntimeError("Provider error with secret that must not be recorded"); }
        if mode == "attempt_confirmation" {
            import from core.incidents { review_cluster_proposal }
            review_cluster_proposal("model-supplied-id", "confirmed", 1);
        }
        if mode in ["stale", "duplicate_ids", "missing"] {
            if mode == "stale" { groups[0].reports[0].revision += 1; }
            if mode == "duplicate_ids" { groups[0].reports.append(groups[0].reports[0]); }
            if mode == "missing" { groups[0].reports[0].id = "nonexistent"; }
        }
        results: list[ClusterAssessment] = [];
        for group in groups {
            result = ClusterAssessment(candidate_group_id=group.candidate_group_id,
                same_incident=mode != "negative",
                confidence=0.6 if mode == "low" else (1.5 if mode == "malformed" else 0.91),
                reasoning_summary="Descriptions and Jac-computed facts identify the same canal bridge waste site.",
                matching_signals=["Shared location terms", "Nearby submitted observations"],
                conflicting_signals=[], suggested_category="illegal_dumping", suggested_severity="medium");
            if mode == "demo_mock" {
                result.suggested_category = group.reports[0].category;
                result.reasoning_summary = "Offline assessment of one deterministic candidate group.";
            }
            results.append(result);
        }
        if mode in ["mock_byllm", "demo_mock", "unknown_group", "missing_assessment", "duplicate_assessment"] {
            if mode == "unknown_group" { results[0].candidate_group_id = "unknown-group"; }
            outputs = [{
                "candidate_group_id": item.candidate_group_id,
                "same_incident": item.same_incident,
                "confidence": item.confidence,
                "reasoning_summary": item.reasoning_summary,
                "matching_signals": item.matching_signals,
                "conflicting_signals": item.conflicting_signals,
                "suggested_category": item.suggested_category,
                "suggested_severity": item.suggested_severity
            } for item in results];
            if mode == "missing_assessment" { outputs.pop(); }
            if mode == "duplicate_assessment" {
                if len(outputs) > 1 { outputs[1] = outputs[0]; }
                else { outputs.append(outputs[0]); }
            }
            llm = MockLLM(outputs=[outputs]);
            assessments = assess_candidates(groups, llm);
            assert len(llm.seen) == 1;
            assert llm.exhausted();
            return assessments;
        }
        return results;
    }
    return run_intelligence(request_id, assessor);
}
