"""Opt-in synthetic fixture generation. No agent or expected cluster membership here."""
import os;
import from datetime { datetime, timezone, timedelta }
import from uuid { uuid5, NAMESPACE_URL }
import from jaclang { JacRuntime as Jac }
import from core.domain { now, require_capability, is_authority }
import from core.reports { Report, IncomingReport, incoming_reports, validate_report }
import from core.intelligence { IntelligenceIndex, IncidentClusterProposal, AgentRun, AgentDecision }
import from agents.incident_intelligence { analysis_lock }

glob DEMO_DATASET: str = "incident-intelligence-demo-v1";

obj SyntheticObservation {
    has description: str, category: str, latitude: float, longitude: float, location_text: str;
}

def synthetic_observations() -> list[SyntheticObservation] {
    # Fictional observations and landmarks. The flat records contain no case labels.
    # Uniform provenance is the only additional metadata passed to normal analysis.
    return [
        SyntheticObservation("Someone has tipped sacks of household rubbish beside the canal footbridge off Nelum Lane. Coconut shells and plastic cover the bank.", "illegal_dumping", 6.9271, 79.8612, "Fictional Nelum Lane canal footbridge — synthetic demonstration"),
        SyntheticObservation("A fresh heap of broken buckets and polythene bags is lying on the canal bank just beyond the small Nelum Lane bridge.", "illegal_dumping", 6.9274, 79.8613, "Fictional Nelum Lane canal footbridge — synthetic demonstration"),
        SyntheticObservation("Walked past the footbridge near Nelum Lane and saw dumped building sacks mixed with food wrappers beside the water, not inside a collection bin.", "illegal_dumping", 6.9269, 79.8616, "Fictional Nelum Lane canal footbridge — synthetic demonstration"),
        SyntheticObservation("Rubbish has been unloaded at the canal crossing on Nelum Lane again. Loose plastic from the pile is blowing toward the waterway.", "illegal_dumping", 6.9275, 79.8617, "Fictional Nelum Lane canal footbridge — synthetic demonstration"),
        SyntheticObservation("The roadside drain outside the Araliya junction tea kade is packed with leaves and rubbish. Rainwater is standing across the lane.", "blocked_drain", 6.9471, 79.8832, "Fictional Araliya junction tea shop drain — synthetic demonstration"),
        SyntheticObservation("Water is backing up from the covered gutter by the little tea shop at Araliya junction. The opening is choked and three-wheelers splash through the pool.", "blocked_drain", 6.9474, 79.8833, "Fictional Araliya junction tea shop drain — synthetic demonstration"),
        SyntheticObservation("After the shower, the same road corner near Araliya tea kade flooded. Plastic wrappers and silt are blocking the drain mouth rather than letting water out.", "blocked_drain", 6.9469, 79.8836, "Fictional Araliya junction tea shop drain — synthetic demonstration"),
        SyntheticObservation("A stagnant puddle reaches the tea shop steps at Araliya junction. The roadside channel is full of debris and the rainwater cannot pass the culvert.", "blocked_drain", 6.9475, 79.8837, "Fictional Araliya junction tea shop drain — synthetic demonstration"),
        SyntheticObservation("At the old Kumbuk bathing steps, the stream has a grey oily film and a sharp chemical smell. This is in the water, not a pile of roadside waste.", "water_pollution", 6.8851, 79.8722, "Fictional Kumbuk stream bathing steps — synthetic demonstration"),
        SyntheticObservation("Saw milky water coming past the Kumbuk washing steps this morning, with foam gathering against the rocks and an unusual smell.", "water_pollution", 6.8854, 79.8723, "Fictional Kumbuk stream bathing steps — synthetic demonstration"),
        SyntheticObservation("The shallow stream beside the Kumbuk bathing place looks discoloured. A greasy layer moves on the surface and the usual clear water has gone cloudy.", "water_pollution", 6.8849, 79.8726, "Fictional Kumbuk stream bathing steps — synthetic demonstration"),
        SyntheticObservation("People at the Kumbuk stone steps noticed frothy grey water and a strong detergent-like odour downstream. Please check the stream contamination.", "water_pollution", 6.8855, 79.8727, "Fictional Kumbuk stream bathing steps — synthetic demonstration"),
        SyntheticObservation("The public waste bins beside the Siyambala pola bus halt are overflowing. Vegetable scraps and shopping bags have spread onto the pavement.", "overflowing_waste", 6.9121, 79.9032, "Fictional Siyambala pola bus halt bins — synthetic demonstration"),
        SyntheticObservation("Both collection bins at the Siyambala market bus stop are already full, with rubbish stacked around their bases and crows pulling out food waste.", "overflowing_waste", 6.9124, 79.9033, "Fictional Siyambala pola bus halt bins — synthetic demonstration"),
        SyntheticObservation("There is no room left in the municipal bins next to Siyambala pola. Waste from the stalls is spilling across the walking space near the bus shelter.", "overflowing_waste", 6.9119, 79.9036, "Fictional Siyambala pola bus halt bins — synthetic demonstration"),
        SyntheticObservation("Uncollected garbage has built up around the public bin enclosure by Siyambala bus halt. Food scraps and plastic are spilling out beside the road.", "overflowing_waste", 6.9125, 79.9037, "Fictional Siyambala pola bus halt bins — synthetic demonstration")
    ];
}

node DemoDataset {
    has name: str, created_by: str, created_at: str, report_ids: list[str];
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
edge DemoDatasetIndex: any --> DemoDataset {
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
obj DemoState {
    has enabled: bool, report_count: int, loaded: bool, can_clear: bool, message: str;
}
obj DemoResult {
    has message: str, reports_loaded: int = 0, reports_removed: int = 0,
        proposals_removed: int = 0, decisions_removed: int = 0,
        runs_removed: int = 0, runs_preserved: int = 0;
}

def demo_enabled() -> bool {
    return os.environ.get("ECOTRACK_ENABLE_DEMO_SEED", "").strip().lower() == "true";
}

def loaded_dataset() -> DemoDataset | None {
    require_capability("agent:read");
    for item in [root.shared ->:DemoDatasetIndex:-> [?:DemoDataset]] {
        if item.name == DEMO_DATASET { return item; }
    }
    return None;
}

def demo_state() -> DemoState {
    require_capability("agent:read");
    dataset = loaded_dataset();
    count = len([item for item in incoming_reports()
        if item.source_type == "demo_seed" and item.demo_dataset == DEMO_DATASET]);
    can_clear = dataset is not None and dataset.created_by == jid(root);
    return DemoState(enabled=demo_enabled(), report_count=count, loaded=dataset is not None,
        can_clear=can_clear, message="" if dataset is None or can_clear else
        "Use the authority account that loaded this dataset to clear it safely.");
}

def require_demo_access() -> None {
    require_capability("demo:manage");
    if not demo_enabled() { raise PermissionError("Demo loading and clearing are disabled on this server."); }
}

def load_demo_dataset() -> DemoResult {
    require_demo_access();
    if not analysis_lock.acquire(blocking=False) { raise ValueError("Intelligence or demo maintenance is running. Retry shortly."); }
    try {
        existing = loaded_dataset();
        if existing is not None {
            return DemoResult(message="Demo dataset already loaded.", reports_loaded=demo_state().report_count);
        }
        # One canonical manifest guards the dataset; observations are newly identified
        # after a clear/reload, so retained audit records never resolve to new evidence.
        dataset = DemoDataset(name=DEMO_DATASET, created_by=jid(root), created_at=now(), report_ids=[]);
        dataset.__jac__.id = uuid5(NAMESPACE_URL, "ecotrack:dataset:" + DEMO_DATASET);
        root ++> dataset;
        root.shared +>:DemoDatasetIndex:+> dataset;
        stamp = datetime.now(timezone.utc);
        for (index, row) in enumerate(synthetic_observations()) {
            submitted = (stamp - timedelta(minutes=index * 7)).isoformat();
            validate_report(row.description, row.category, row.latitude, row.longitude,
                row.location_text, "synthetic-demo-observation");
            item = dataset ++> Report(reporter_id="demo_seed", description=row.description,
                category=row.category, latitude=row.latitude, longitude=row.longitude,
                location_text=row.location_text, submitted_at=submitted, created_at=submitted,
                updated_at=submitted, source_type="demo_seed", demo_dataset=DEMO_DATASET);
            root.shared +>:IncomingReport:+> item;
            dataset.report_ids.append(jid(item));
        }
        Jac.commit();
        return DemoResult(message="16 Demo Reports Loaded", reports_loaded=16);
    } finally { analysis_lock.release(); }
}

def require_owned(item: any) -> None {
    if item.__jac__.root != root.__jac__.id {
        raise PermissionError("Another authority owns related demo records. Cleanup was refused without deleting anything.");
    }
}

def clear_demo_dataset() -> DemoResult {
    require_demo_access();
    if not analysis_lock.acquire(blocking=False) { raise ValueError("Intelligence or demo maintenance is running. Retry shortly."); }
    try {
        dataset = loaded_dataset();
        if dataset is None { return DemoResult(message="No demo dataset is loaded."); }
        if dataset.created_by != jid(root) { raise PermissionError("Only the authority that loaded this dataset can clear it safely."); }
        require_owned(dataset);
        ids = set(dataset.report_ids);
        reports = [item for item in [root.shared ->:IncomingReport:-> [?:Report]] if jid(item) in ids];
        # Validate the entire deletion plan before deleting anything.
        for item in reports {
            if item.source_type != "demo_seed" or item.demo_dataset != DEMO_DATASET {
                raise ValueError("Dataset provenance does not match. Nothing was deleted.");
            }
            require_owned(item);
        }
        proposals = [item for item in [root.shared ->:IntelligenceIndex:-> [?:IncidentClusterProposal]]
            if set(item.report_ids) & ids];
        for item in proposals {
            if not set(item.report_ids) <= ids {
                raise ValueError("A proposal also references genuine or unrelated reports. Cleanup was refused to preserve that evidence.");
            }
            require_owned(item);
        }
        decisions = [item for item in [root.shared ->:IntelligenceIndex:-> [?:AgentDecision]]
            if set(item.report_ids) & ids];
        for item in decisions {
            if not set(item.report_ids) <= ids {
                raise ValueError("A decision mixes genuine and synthetic evidence. Nothing was deleted.");
            }
            require_owned(item);
        }
        run_ids = {item.agent_run_id for item in proposals} | {item.agent_run_id for item in decisions};
        all_decisions = [root.shared ->:IntelligenceIndex:-> [?:AgentDecision]];
        all_proposals = [root.shared ->:IntelligenceIndex:-> [?:IncidentClusterProposal]];
        removable_runs: list[AgentRun] = [];
        preserved = 0;
        for item in [root.shared ->:IntelligenceIndex:-> [?:AgentRun]] {
            if jid(item) not in run_ids { continue; }
            references = [set(value.report_ids) for value in all_decisions if value.agent_run_id == jid(item)] +
                         [set(value.report_ids) for value in all_proposals if value.agent_run_id == jid(item)];
            # Without an examined-report manifest, only a full demo-only run can
            # safely be removed. Mixed/opaque history stays intact.
            if item.reports_examined == len(ids) and references and all([value <= ids for value in references]) {
                require_owned(item); removable_runs.append(item);
            } else { preserved += 1; }
        }
        result = DemoResult(message="Demo dataset cleared. Genuine reports and unrelated/mixed run history were preserved.",
            reports_removed=len(reports), proposals_removed=len(proposals), decisions_removed=len(decisions),
            runs_removed=len(removable_runs), runs_preserved=preserved);
        for item in proposals { del item; }
        for item in decisions { del item; }
        for item in removable_runs { del item; }
        for item in reports { del item; }
        del dataset;
        Jac.commit();
        return result;
    } finally { analysis_lock.release(); }
}
