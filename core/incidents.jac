"""Authority confirmation boundary. Agent output remains a proposal until reviewed."""
import from uuid { uuid5, NAMESPACE_URL }
import from jaclang { JacRuntime as Jac }
import from core.domain { require_capability, is_authority, can_read_responses, now }
import from core.reports { REPORT_CATEGORIES, incoming_reports }
import from core.intelligence { IncidentClusterProposal, IntelligenceIndex }
import from agents.incident_intelligence { analysis_lock }
import from contracts.incident_views { IncidentView, HumanReviewView }

node Incident {
    has category: str, severity: str, report_ids: list[str], created_at: str,
        updated_at: str, confirmed_at: str, confirmed_by: str, source_proposal_id: str,
        status: str = "confirmed", revision: int = 1;
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.WRITE; }
        if can_read_responses() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
node HumanIncidentReview {
    has proposal_id: str, reviewer: str, timestamp: str, previous_status: str,
        resulting_status: str, proposal_revision: int, incident_id: str;
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
edge IncidentIndex: any --> any {
    def __jac_access__ -> AccessLevel {
        if can_read_responses() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}

def incident_view(item: Incident) -> IncidentView {
    return IncidentView(incident_id=jid(item), category=item.category, severity=item.severity,
        status=item.status, report_ids=list(item.report_ids), created_at=item.created_at,
        updated_at=item.updated_at, confirmed_at=item.confirmed_at, confirmed_by=item.confirmed_by,
        source_proposal_id=item.source_proposal_id, revision=item.revision);
}
def human_review_view(item: HumanIncidentReview) -> HumanReviewView {
    return HumanReviewView(proposal_id=item.proposal_id, reviewer=item.reviewer,
        timestamp=item.timestamp, previous_status=item.previous_status,
        resulting_status=item.resulting_status, proposal_revision=item.proposal_revision,
        incident_id=item.incident_id);
}
def list_confirmed_incidents() -> list[IncidentView] {
    require_capability("incident:read");
    return [incident_view(item) for item in [root.shared ->:IncidentIndex:-> [?:Incident, -confirmed_at]]
        if item.status == "confirmed"];
}
def list_human_reviews() -> list[HumanReviewView] {
    require_capability("audit:read");
    return [human_review_view(item) for item in [root.shared ->:IncidentIndex:-> [?:HumanIncidentReview, -timestamp]]];
}
def review_cluster_proposal(proposal_id: str, decision: str, expected_revision: int) -> HumanReviewView {
    require_capability("incident:review_cluster");
    if decision == "confirmed" { require_capability("incident:confirm"); }
    if decision not in ["confirmed", "rejected"] { raise ValueError("Choose confirmed or rejected."); }
    # The agent holds this lock throughout assessment. Neither model tools nor an
    # injected assessor can confirm a proposal from inside an active agent run.
    if not analysis_lock.acquire(blocking=False) {
        raise ValueError("Analysis or maintenance is running. Review after it finishes.");
    }
    try {
        Jac.commit();
        Jac.get_context().mem.read_barrier();
        for proposal in [root.shared ->:IntelligenceIndex:-> [?:IncidentClusterProposal]] {
            if jid(proposal) != proposal_id { continue; }
            if proposal.revision != expected_revision { raise ValueError("Proposal changed. Refresh before reviewing."); }
            if proposal.status != "pending_review" { raise ValueError("This proposal has already been reviewed."); }
            for item in [root.shared ->:IncidentIndex:-> [?:Incident]] {
                if item.source_proposal_id == proposal_id { raise ValueError("An Incident already exists for this proposal."); }
            }
            incident_id = "";
            stamp = now();
            if decision == "confirmed" {
                ids = proposal.report_ids;
                available = {item.id for item in incoming_reports()};
                if len(ids) < 2 or len(ids) != len(set(ids)) or not set(ids) <= available {
                    raise ValueError("Source reports are missing or invalid. Confirmation refused.");
                }
                if proposal.suggested_category not in REPORT_CATEGORIES or proposal.suggested_severity not in ["low", "medium", "high", "critical"] {
                    raise ValueError("Proposal category or severity is invalid.");
                }
                incident = Incident(category=proposal.suggested_category, severity=proposal.suggested_severity,
                    report_ids=sorted(ids), created_at=stamp, updated_at=stamp,
                    confirmed_at=stamp, confirmed_by=jid(root), source_proposal_id=proposal_id);
                # One canonical anchor per proposal also protects against concurrent inserts.
                incident.__jac__.id = uuid5(NAMESPACE_URL, "ecotrack:incident:" + proposal_id);
                root ++> incident;
                root.shared +>:IncidentIndex:+> incident;
                incident_id = jid(incident);
            }
            proposal.status = decision;
            proposal.reviewed_by = jid(root); proposal.reviewed_at = stamp;
            proposal.updated_at = stamp; proposal.revision += 1; proposal.incident_id = incident_id;
            review = root ++> HumanIncidentReview(proposal_id=proposal_id, reviewer=jid(root),
                timestamp=stamp, previous_status="pending_review", resulting_status=decision,
                proposal_revision=proposal.revision, incident_id=incident_id);
            root.shared +>:IncidentIndex:+> review;
            Jac.commit();
            return human_review_view(review);
        }
        raise ValueError("Proposal not found.");
    } finally { analysis_lock.release(); }
}
