"""Read-only model tools, restricted to one authorized candidate snapshot."""
import from contracts.report_views { ReportView }
import re;
import from core.domain { require_capability }
import from core.reports { incoming_reports }
import from core.intelligence { CandidateGroup, PairSignal, calculate_report_distance, report_snapshot }

obj CandidateTools {
    has group: CandidateGroup;

    def get_report_context(report_id: str) -> ReportView {
        require_capability("agent:run_intelligence");
        for observation in self.group.reports {
            if observation.id == report_id {
                # A scoped ID selects an already authorized observation; recheck current access.
                for current in incoming_reports() {
                    if current.id == report_id and report_snapshot(current) == report_snapshot(observation) { return current; }
                }
                raise ValueError("Report context is stale or unavailable.");
            }
        }
        raise PermissionError("Tool access is restricted to this candidate group.");
    }

    def report_distance(first_id: str, second_id: str) -> float {
        return calculate_report_distance(self.get_report_context(first_id), self.get_report_context(second_id));
    }

    def compare_report_content(first_id: str, second_id: str) -> list[str] {
        first = self.get_report_context(first_id); second = self.get_report_context(second_id);
        # Lexical overlap is supporting evidence only, never a semantic verdict.
        first_words = set(re.findall("[a-z]{4,}", first.description.lower()));
        second_words = set(re.findall("[a-z]{4,}", second.description.lower()));
        return sorted(list(first_words & second_words))[:30];
    }
}
sem CandidateTools.get_report_context = "Read one real observation in this candidate group; excludes reporter identity.";
sem CandidateTools.report_distance = "Get server-calculated Haversine distance in meters between two candidate reports.";
sem CandidateTools.compare_report_content = "Read shared description words as a lexical signal; overlap alone is not proof of the same incident.";
