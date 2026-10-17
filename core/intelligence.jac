"""Proposal-only intelligence domain: deterministic evidence and guarded persistence."""
import from contracts.report_views { ReportView }
import os;
import from uuid { uuid5, NAMESPACE_URL }
import from math { radians, sin, cos, asin, sqrt, isfinite }
import from datetime { datetime }
import re;
import from core.domain { now, is_authority, require_capability }
import from core.reports { REPORT_CATEGORIES, incoming_reports }

obj IntelligenceConfig {
    has radius_meters: float = 250.0, time_window_hours: float = 72.0,
        location_overlap_threshold: float = 0.25,
        description_overlap_threshold: float = 0.20,
        min_candidate_score: float = 0.50,
        confidence_threshold: float = 0.70, max_reports: int = 200,
        max_groups: int = 10, max_group_size: int = 8;
}

def intelligence_config() -> IntelligenceConfig {
    config = IntelligenceConfig(
        radius_meters=float(os.environ.get("ECOTRACK_DUPLICATE_RADIUS_METERS", "250")),
        time_window_hours=float(os.environ.get("ECOTRACK_DUPLICATE_TIME_WINDOW_HOURS", "72")),
        location_overlap_threshold=float(os.environ.get("ECOTRACK_DUPLICATE_LOCATION_OVERLAP", "0.25")),
        description_overlap_threshold=float(os.environ.get("ECOTRACK_DUPLICATE_DESCRIPTION_OVERLAP", "0.20")),
        min_candidate_score=float(os.environ.get("ECOTRACK_DUPLICATE_MIN_SCORE", "0.50")),
        confidence_threshold=float(os.environ.get("ECOTRACK_CLUSTER_CONFIDENCE_THRESHOLD", "0.70")));
    if (not isfinite(config.radius_meters) or not 0 < config.radius_meters <= 10000
        or not isfinite(config.time_window_hours) or not 0 < config.time_window_hours <= 8760
        or not 0 <= config.location_overlap_threshold <= 1
        or not 0 <= config.description_overlap_threshold <= 1
        or not 0 <= config.min_candidate_score <= 1
        or not isfinite(config.confidence_threshold) or not 0 <= config.confidence_threshold <= 1) {
        raise ValueError("Invalid intelligence configuration. Check radius, time, overlap, score and confidence thresholds.");
    }
    return config;
}

obj PairSignal {
    has first_id: str, second_id: str, distance_meters: float, time_difference_hours: float,
        category_relation: str, compatibility_score: float,
        location_overlap_words: list[str], description_overlap_words: list[str];
}

obj CandidateGroup {
    has candidate_group_id: str, reports: list[ReportView], signals: list[PairSignal];
}

obj CandidateEvidence {
    has id: str, category: str, description: str, location_text: str;
}

obj CandidateBatch {
    has candidate_group_id: str, reports: list[CandidateEvidence], signals: list[PairSignal];
}

obj ClusterAssessment {
    has candidate_group_id: str, same_incident: bool, confidence: float, reasoning_summary: str,
        matching_signals: list[str], conflicting_signals: list[str],
        suggested_category: str, suggested_severity: str;
}
sem CandidateBatch = "Compact report evidence and Jac-computed pair facts for one deterministic candidate group.";
sem ClusterAssessment = "A tentative semantic assessment for one candidate group; never a confirmed incident.";
sem ClusterAssessment.candidate_group_id = "Copy the exact ID of the candidate group being assessed.";
sem ClusterAssessment.confidence = "Finite confidence from 0 to 1. Uncertainty and conflicting evidence reduce confidence.";
sem ClusterAssessment.reasoning_summary = "Concise public evidence rationale, not private internal reasoning; at most 1500 characters.";
sem ClusterAssessment.suggested_category = "One of illegal_dumping, overflowing_waste, water_pollution, blocked_drain, damaged_public_space, other.";
sem ClusterAssessment.suggested_severity = "One of low, medium, high, critical; a suggestion only.";

# All distances are computed here, never by the model.
def calculate_report_distance(first: ReportView, second: ReportView) -> float {
    lat1 = radians(first.latitude); lat2 = radians(second.latitude);
    dlat = lat2 - lat1; dlon = radians(second.longitude - first.longitude);
    value = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2;
    return 6371008.8 * 2 * asin(sqrt(min(1.0, max(0.0, value))));
}

def compatible_category_relation(first: str, second: str) -> str {
    if first == second { return "same"; }
    compatible = [
        ("illegal_dumping", "overflowing_waste"),
        ("illegal_dumping", "damaged_public_space"),
        ("overflowing_waste", "damaged_public_space"),
        ("overflowing_waste", "blocked_drain"),
        ("damaged_public_space", "blocked_drain")
    ];
    if (first, second) in compatible or (second, first) in compatible { return "related"; }
    return "";
}

def lexical_tokens(value: str) -> set[str] {
    ignored = ["the", "and", "for", "with", "from", "near", "beside", "next", "same",
        "this", "that", "there", "have", "has", "was", "were", "into", "onto", "along",
        "area", "place", "road", "roadside", "report", "issue", "waste", "rubbish",
        "garbage", "water", "fictional", "synthetic", "demonstration"];
    return {word for word in re.findall("[a-z0-9]{3,}", value.lower()) if word not in ignored};
}

def overlap_words(first: str, second: str) -> list[str] {
    return sorted(list(lexical_tokens(first) & lexical_tokens(second)));
}

def overlap_ratio(first: str, second: str) -> float {
    first_words = lexical_tokens(first);
    second_words = lexical_tokens(second);
    if not first_words or not second_words { return 0.0; }
    return len(first_words & second_words) / min(len(first_words), len(second_words));
}

def candidate_signal(first: ReportView, second: ReportView, config: IntelligenceConfig) -> PairSignal | None {
    if first.id == second.id or first.status != "submitted" or second.status != "submitted" { return None; }
    category_relation = compatible_category_relation(first.category, second.category);
    if category_relation == "" { return None; }
    hours = abs((datetime.fromisoformat(first.submitted_at) - datetime.fromisoformat(second.submitted_at)).total_seconds()) / 3600;
    distance = calculate_report_distance(first, second);
    if hours > config.time_window_hours or distance > config.radius_meters { return None; }
    location_words = overlap_words(first.location_text, second.location_text);
    description_words = overlap_words(first.description, second.description);
    location_score = overlap_ratio(first.location_text, second.location_text);
    description_score = overlap_ratio(first.description, second.description);
    if (location_score < config.location_overlap_threshold
        and description_score < config.description_overlap_threshold) { return None; }
    geographic_score = 1.0 - distance / config.radius_meters;
    temporal_score = 1.0 - hours / config.time_window_hours;
    category_score = 1.0 if category_relation == "same" else 0.75;
    score = 0.20 * geographic_score + 0.10 * temporal_score + 0.20 * category_score
        + 0.25 * location_score + 0.25 * description_score;
    if score < config.min_candidate_score { return None; }
    return PairSignal(first_id=first.id, second_id=second.id,
        distance_meters=round(distance, 2), time_difference_hours=round(hours, 3),
        category_relation=category_relation, compatibility_score=round(score, 4),
        location_overlap_words=location_words, description_overlap_words=description_words);
}

def candidate_group_id(reports: list[ReportView]) -> str {
    ids = sorted([item.id for item in reports]);
    return str(uuid5(NAMESPACE_URL, "ecotrack:candidate:" + ",".join(ids)));
}

def count_candidate_relationships(reports: list[ReportView], config: IntelligenceConfig) -> int {
    eligible = sorted([item for item in reports if item.status == "submitted"],
        key=lambda (item: ReportView) { (item.submitted_at, item.id); }, reverse=True)[:config.max_reports];
    count = 0;
    for i in range(len(eligible)) {
        for j in range(i + 1, len(eligible)) {
            if candidate_signal(eligible[i], eligible[j], config) is not None { count += 1; }
        }
    }
    return count;
}

def find_candidate_reports(reports: list[ReportView], config: IntelligenceConfig) -> list[CandidateGroup] {
    # Complete-link greedy groups: every member must match every other member.
    # Unlike connected components, a chain cannot bridge arbitrarily distant sites.
    eligible = sorted([item for item in reports if item.status == "submitted"],
        key=lambda (item: ReportView) { (item.submitted_at, item.id); }, reverse=True)[:config.max_reports];
    groups: list[CandidateGroup] = [];
    seen: set[str] = set();
    for item in eligible {
        if item.id in seen { continue; }
        seen.add(item.id);
        placed = False;
        for group in groups {
            if len(group.reports) >= config.max_group_size { continue; }
            signals: list[PairSignal] = [];
            for member in group.reports {
                signal = candidate_signal(item, member, config);
                if signal is not None { signals.append(signal); }
            }
            if len(signals) == len(group.reports) {
                group.reports.append(item);
                group.candidate_group_id = candidate_group_id(group.reports);
                group.signals.extend(signals);
                placed = True; break;
            }
        }
        if not placed {
            groups.append(CandidateGroup(candidate_group_id=candidate_group_id([item]), reports=[item], signals=[]));
        }
    }
    return [group for group in groups if len(group.reports) >= 2][:config.max_groups];
}

def compact_candidate_groups(groups: list[CandidateGroup]) -> list[CandidateBatch] {
    return [CandidateBatch(candidate_group_id=group.candidate_group_id,
        reports=[CandidateEvidence(id=item.id, category=item.category,
            description=item.description, location_text=item.location_text) for item in group.reports],
        signals=group.signals) for group in groups];
}

node IncidentClusterProposal {
    has report_ids: list[str], confidence: float, suggested_category: str,
        suggested_severity: str, reasoning_summary: str, matching_signals: list[str],
        conflicting_signals: list[str], signals: list[PairSignal], agent_run_id: str,
        status: str = "pending_review", created_at: str = "", updated_at: str = "", revision: int = 1,
        reviewed_by: str = "", reviewed_at: str = "", incident_id: str = "";
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.WRITE; }
        return AccessLevel.NO_ACCESS;
    }
}
node AgentRun {
    has requested_by: str, request_id: str, model: str, configuration: IntelligenceConfig,
        agent_name: str = "Incident Intelligence Agent", started_at: str = "", completed_at: str = "",
        status: str = "running", reports_examined: int = 0, candidate_relationships: int = 0,
        candidate_groups_examined: int = 0, llm_requests: int = 0,
        proposals_created: int = 0, error_summary: str = "", summary: str = "",
        incident_id: str = "", organizations_considered: int = 0, existing_lead_id: str = "";
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
node AgentDecision {
    has agent_run_id: str, decision_type: str, report_ids: list[str], signals: list[PairSignal],
        confidence: float | None, reasoning_summary: str, timestamp: str;
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
edge IntelligenceIndex: any --> any {
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}

obj ProposalView {
    has proposal_id: str, report_ids: list[str], reports: list[ReportView],
        confidence: float, suggested_category: str, suggested_severity: str,
        reasoning_summary: str, matching_signals: list[str], conflicting_signals: list[str],
        signals: list[PairSignal], status: str, created_at: str, updated_at: str,
        agent_run_id: str, revision: int,
        reviewed_by: str = "", reviewed_at: str = "", incident_id: str = "";
}
obj DecisionView {
    has id: str, agent_run_id: str, decision_type: str, report_ids: list[str],
        signals: list[PairSignal], confidence: float | None, reasoning_summary: str, timestamp: str;
}
obj RunView {
    has id: str, agent_name: str, model: str, configuration: IntelligenceConfig,
        started_at: str, completed_at: str, status: str,
        reports_examined: int, candidate_relationships: int, candidate_groups_examined: int,
        llm_requests: int, proposals_created: int,
        error_summary: str, summary: str,
        incident_id: str = "", organizations_considered: int = 0, existing_lead_id: str = "";
}
obj IntelligenceView {
    has proposals: list[ProposalView], runs: list[RunView], decisions: list[DecisionView];
}

def run_view(item: AgentRun) -> RunView {
    return RunView(id=jid(item), agent_name=item.agent_name, model=item.model,
        configuration=item.configuration, started_at=item.started_at, completed_at=item.completed_at,
        status=item.status, reports_examined=item.reports_examined,
        candidate_relationships=item.candidate_relationships,
        candidate_groups_examined=item.candidate_groups_examined, llm_requests=item.llm_requests,
        proposals_created=item.proposals_created,
        error_summary=item.error_summary, summary=item.summary, incident_id=item.incident_id,
        organizations_considered=item.organizations_considered, existing_lead_id=item.existing_lead_id);
}

def intelligence_state() -> IntelligenceView {
    require_capability("agent:read");
    reports = {item.id: item for item in incoming_reports()};
    proposals = [ProposalView(proposal_id=jid(item), report_ids=item.report_ids,
        reports=[reports[id] for id in item.report_ids if id in reports], confidence=item.confidence,
        suggested_category=item.suggested_category, suggested_severity=item.suggested_severity,
        reasoning_summary=item.reasoning_summary, matching_signals=item.matching_signals,
        conflicting_signals=item.conflicting_signals, signals=item.signals, status=item.status,
        created_at=item.created_at, updated_at=item.updated_at, agent_run_id=item.agent_run_id,
        revision=item.revision, reviewed_by=item.reviewed_by, reviewed_at=item.reviewed_at,
        incident_id=item.incident_id)
        for item in [root.shared ->:IntelligenceIndex:-> [?:IncidentClusterProposal, -created_at]]];
    runs = [run_view(item) for item in [root.shared ->:IntelligenceIndex:-> [?:AgentRun, -started_at]]];
    decisions = [DecisionView(id=jid(item), agent_run_id=item.agent_run_id,
        decision_type=item.decision_type, report_ids=item.report_ids, signals=item.signals,
        confidence=item.confidence, reasoning_summary=item.reasoning_summary, timestamp=item.timestamp)
        for item in [root.shared ->:IntelligenceIndex:-> [?:AgentDecision, -timestamp]]];
    return IntelligenceView(proposals=proposals, runs=runs, decisions=decisions);
}

def validate_assessment(value: ClusterAssessment) -> None {
    if (not isinstance(value, ClusterAssessment) or not value.candidate_group_id.strip()
        or len(value.candidate_group_id) > 100
        or type(value.same_incident) is not bool
        or not isfinite(value.confidence) or not 0 <= value.confidence <= 1
        or value.suggested_category not in REPORT_CATEGORIES
        or value.suggested_severity not in ["low", "medium", "high", "critical"]
        or not value.reasoning_summary.strip() or len(value.reasoning_summary) > 1500) {
        raise ValueError("The model returned an invalid structured assessment.");
    }
    for signals in [value.matching_signals, value.conflicting_signals] {
        if not isinstance(signals, list) or len(signals) > 12 { raise ValueError("Invalid assessment signals."); }
        for signal in signals {
            if not isinstance(signal, str) or not signal.strip() or len(signal) > 500 {
                raise ValueError("Invalid assessment signal.");
            }
        }
    }
}

def validate_assessments(values: list[ClusterAssessment], groups: list[CandidateGroup]) -> dict[str, ClusterAssessment] {
    if not isinstance(values, list) or len(values) != len(groups) {
        raise ValueError("The model must return exactly one assessment for every candidate group.");
    }
    expected = {group.candidate_group_id for group in groups};
    checked: dict[str, ClusterAssessment] = {};
    for group in groups {
        if group.candidate_group_id != candidate_group_id(group.reports) {
            raise ValueError("The candidate group ID does not match its deterministic report membership.");
        }
    }
    for value in values {
        validate_assessment(value);
        if value.candidate_group_id not in expected or value.candidate_group_id in checked {
            raise ValueError("The model returned a missing, duplicate or unknown candidate group ID.");
        }
        checked[value.candidate_group_id] = value;
    }
    if set(checked.keys()) != expected {
        raise ValueError("The model omitted a candidate group assessment.");
    }
    return checked;
}

def report_snapshot(item: ReportView) -> tuple[any, ...] {
    # Jac objects have graph identity; compare data fields, not object identity.
    return (item.id, item.revision, item.status, item.description, item.category,
        item.latitude, item.longitude, item.location_text, item.evidence_ref,
        item.submitted_at, item.created_at, item.updated_at);
}

def validate_candidate(group: CandidateGroup, config: IntelligenceConfig) -> CandidateGroup {
    require_capability("agent:run_intelligence");
    ids = [item.id for item in group.reports];
    if len(ids) != len(set(ids)) or not 2 <= len(ids) <= config.max_group_size {
        raise ValueError("A proposal requires distinct reports within the group limit.");
    }
    available = {item.id: item for item in incoming_reports()};
    current: list[ReportView] = [];
    for item in group.reports {
        if item.id not in available or report_snapshot(available[item.id]) != report_snapshot(item) {
            raise ValueError("A report is missing or stale. Run analysis again.");
        }
        current.append(available[item.id]);
    }
    signals: list[PairSignal] = [];
    for i in range(len(current)) {
        for j in range(i + 1, len(current)) {
            signal = candidate_signal(current[i], current[j], config);
            if signal is None { raise ValueError("Report references no longer form an eligible candidate group."); }
            signals.append(signal);
        }
    }
    return CandidateGroup(candidate_group_id=candidate_group_id(current), reports=current, signals=signals);
}

def create_cluster_proposal(group: CandidateGroup, assessment: ClusterAssessment,
                            run: AgentRun, config: IntelligenceConfig) -> bool {
    require_capability("agent:run_intelligence");
    if run.requested_by != jid(root) or run.status != "running" {
        raise PermissionError("An active authorized agent run is required.");
    }
    validate_assessment(assessment);
    checked = validate_candidate(group, config);
    if not assessment.same_incident or assessment.confidence < config.confidence_threshold { return False; }
    ids = sorted([item.id for item in checked.reports]);
    for item in [root.shared ->:IntelligenceIndex:-> [?:IncidentClusterProposal]] {
        if item.report_ids == ids { return False; }
    }
    stamp = now();
    proposal = IncidentClusterProposal(report_ids=ids, confidence=assessment.confidence,
        suggested_category=assessment.suggested_category, suggested_severity=assessment.suggested_severity,
        reasoning_summary=assessment.reasoning_summary, matching_signals=assessment.matching_signals,
        conflicting_signals=assessment.conflicting_signals, signals=checked.signals,
        agent_run_id=jid(run), created_at=stamp, updated_at=stamp);
    # Canonical native anchor ID gives the report set one persistent identity even
    # across authority accounts/workers; storage conflicts cannot insert a second set.
    proposal.__jac__.id = uuid5(NAMESPACE_URL, "ecotrack:cluster:" + ",".join(ids));
    root ++> proposal;
    root.shared +>:IntelligenceIndex:+> proposal;
    return True;
}
