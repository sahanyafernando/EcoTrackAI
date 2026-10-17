"""Authority-only persisted intelligence views; opening a page never invokes a model."""
import type from contracts.report_views { ReportView }
import from endpoints { IntelligenceView, RunView, incident_intelligence_state, run_incident_intelligence, DemoState, demo_dataset_status, load_demo, clear_demo }
import from .DateTime { DateTime }
import from .ReportCard { ReportCard }
import from .Icon { Icon }

def:pub RunSummary(item: RunView) -> JsxElement {
    <article>
        <div className="actions"><h3>{item.agent_name}</h3><span className={"badge " + ("rejected" if item.status == "failed" else ("pending" if item.status == "running" else "verified"))}>{item.status}</span></div>
        <p className="muted"><DateTime value={item.started_at}/> · {item.model}</p>
        <div className="button-row"><span>Reports examined: <strong>{item.reports_examined}</strong></span><span>Candidate relationships: <strong>{item.candidate_relationships}</strong></span><span>Candidate groups: <strong>{item.candidate_groups_examined}</strong></span><span>LLM requests: <strong>{item.llm_requests}</strong></span><span>Proposals created: <strong>{item.proposals_created}</strong></span></div>
        <p>{item.summary}</p>
        {item.error_summary != "" and <p role="alert" className="notice error">{item.error_summary}</p>}
        <details><summary>Run details</summary><p className="details">Run {item.id}</p><p>Radius: {item.configuration.radius_meters} m · Time window: {item.configuration.time_window_hours} hours · Confidence threshold: {round(item.configuration.confidence_threshold * 100)}%</p><p>Limits: {item.configuration.max_reports} reports, {item.configuration.max_groups} groups, {item.configuration.max_group_size} reports per group.</p>{item.completed_at != "" and <p>Completed <DateTime value={item.completed_at}/></p>}</details>
    </article>
}

def:pub ProposalReportList(reports: list[ReportView]) -> JsxElement {
    <div>{[<ReportCard key={item.id} item={item}/> for item in reports]}</div>
}

def:pub IntelligencePage(activity: bool = False, onDemoChanged: Callable[[], None] | None = None) -> JsxElement {
    has state: IntelligenceView | None = None, demoState: DemoState | None = None, demoError: str = "", loading: bool = True,
        running: bool = False, feedback: str = "", loadError: str = "",
        sending: Ref[bool] = Ref(False), requestId: Ref[str] = Ref("");
    can with entry { load(); }
    async def load -> None {
        loading = True; loadError = "";
        try { state = await incident_intelligence_state(); }
        except Exception { loadError = "Intelligence records could not be loaded. Refresh to retry."; }
        finally { loading = False; }
        try { demoState = await demo_dataset_status(); demoError = ""; }
        except Exception { demoError = "Demo availability could not be checked. Refresh intelligence to retry."; }
    }
    async def analyze -> None {
        if sending.current { return; }
        sending.current = True; running = True; feedback = "";
        if requestId.current == "" { requestId.current = globalThis.crypto.randomUUID(); }
        try {
            result = await run_incident_intelligence(request_id=requestId.current or "");
            requestId.current = "";
            feedback = result.error_summary if result.status == "failed" else result.summary;
            await load();
        } except Exception {
            feedback = "Analysis could not be requested or is already running. Refresh Agent Activity before retrying. A retry uses the same request ID.";
        } finally { sending.current = False; running = False; }
    }
    async def manageDemo(clear: bool) -> None {
        if sending.current { return; }
        sending.current = True; running = True; feedback = "";
        try {
            result = await clear_demo() if clear else await load_demo();
            feedback = result.message;
            requestId.current = "";
            await load();
            if onDemoChanged is not None { onDemoChanged(); }
        } except Exception as error {
            feedback = "Demo operation refused or unavailable: " + str(error);
        } finally { sending.current = False; running = False; }
    }
    <div>
        <section className="panel"><p className="eyebrow">Central Authority · Human review required</p><h2>{"Agent Activity" if activity else "Incident Intelligence"}</h2><p>{"Real agent runs and concise evidence decisions." if activity else "Discover related observations. Every cluster is a proposal; original reports remain unchanged."}</p></section>
        {not activity and demoError != "" and <p className="notice" role="status">{demoError}</p>}
        {not activity and demoState is not None and demoState.enabled and <section className="panel">
            <div className="actions"><div><span className="badge planned">Synthetic demo</span><h3>{str(demoState.report_count) + " Demo Reports Loaded"}</h3><p className="muted">Fictional Sri Lankan-style observations. The normal agent must discover related reports; no proposals are preloaded.</p></div>
                <div className="button-row"><button className="quiet" disabled={running or loading} onClick={lambda { manageDemo(False); }}>Load Demo Dataset</button>
                <button className="danger-outline" disabled={running or loading or not demoState.can_clear} onClick={lambda { manageDemo(True); }}>Clear Demo Dataset</button></div>
            </div><p className="muted">Cleanup preserves genuine reports and refuses mixed proposals. Load, analyse and clear using the same authority account.</p>
            {demoState.message != "" and <p className="notice">{demoState.message}</p>}
        </section>}
        <section className="panel"><div className="actions"><div><h3>{"Execution history" if activity else "Authority-controlled analysis"}</h3><p className="muted">Opening this page never calls a model.</p></div><div className="button-row"><button className="quiet" disabled={loading or running} onClick={load}>Refresh intelligence</button>{not activity and <button disabled={loading or running or loadError != ""} onClick={analyze}>{"Analyzing candidates…" if running else "Run Incident Intelligence"}</button>}</div></div>
            {running and <p role="status">Comparing plausible report groups. Analysis may take a few minutes; keep this page open.</p>}
            {feedback != "" and <p className="notice" role="status" aria-live="polite">{feedback}</p>}
            {loading and <p role="status">Loading intelligence records…</p>}
            {loadError != "" and <p className="notice error" role="alert">{loadError}</p>}
            {state is not None and loadError == "" and len(state.runs) == 0 and <div className="empty-state"><Icon name="activity"/><h3>No analysis runs yet</h3><p>Configure a hosted model and provider key on the server, then run Incident Intelligence.</p></div>}
            {state is not None and not activity and len(state.runs) > 0 and <div><h3>Last analysis</h3><RunSummary item={state.runs[0]}/></div>}
        </section>
        {state is not None and loadError == "" and not activity and <section className="panel"><h2>Cluster Proposals ({len(state.proposals)})</h2><p className="muted">Model confidence is a suggestion, not verified truth. Task 4 will add Review/Confirm actions.</p>
            {len(state.proposals) == 0 and <div className="empty-state"><Icon name="incidents"/><h3>No cluster proposals</h3><p>Only real, validated model output appears here. Nearby reports may still describe different problems.</p></div>}
            {[<article key={item.proposal_id}>
                <div className="actions"><h3>Proposed {item.suggested_category.replace("_", " ")}</h3><span className="badge pending">Pending review</span></div>
                <p className="details">Proposal {item.proposal_id}</p><p className="details">{len(item.report_ids)} source reports · Report IDs: {", ".join(item.report_ids)}</p><div className="button-row"><strong>{round(item.confidence * 100)}% confidence</strong><span>Suggested severity: {item.suggested_severity}</span></div>
                <h4>Why the agent grouped these</h4><p className="details">{item.reasoning_summary}</p>
                <ul>{[<li key={str(index)}>{signal}</li> for (index, signal) in enumerate(item.matching_signals)]}</ul>
                <h4>Conflicting signals</h4>{len(item.conflicting_signals) == 0 and <p className="muted">None reported by the model; this does not establish certainty.</p>}
                <ul>{[<li key={str(index)}>{signal}</li> for (index, signal) in enumerate(item.conflicting_signals)]}</ul>
                <details><summary>Reports and deterministic distances ({len(item.report_ids)})</summary>
                    <p className="details">Report IDs: {", ".join(item.report_ids)}</p>
                    <ProposalReportList reports={item.reports}/>
                    {len(item.reports) != len(item.report_ids) and <p className="notice error">Some referenced reports are unavailable. This proposal requires revalidation before any future approval.</p>}
                    {[<p key={signal.first_id + signal.second_id} className="details"><code>{signal.first_id}</code> ↔ <code>{signal.second_id}</code>: {signal.distance_meters} m · {signal.time_difference_hours} hours apart</p> for signal in item.signals]}
                </details>
                <p className="muted">Created <DateTime value={item.created_at}/></p><p className="details muted">Agent run {item.agent_run_id} · revision {item.revision}</p>
            </article> for item in state.proposals]}
        </section>}
        {state is not None and loadError == "" and activity and <section className="panel"><h2>Incident Intelligence runs</h2>
            {[<div key={item.id}><RunSummary item={item}/><details><summary>Decision records</summary>
                {[<article key={decision.id}><h4>{decision.decision_type.replace("_", " ")}</h4><p className="details">{decision.reasoning_summary}</p><p className="details">Reports: {", ".join(decision.report_ids)}</p>{decision.confidence is not None and <p>Model confidence: {round(decision.confidence * 100)}%</p>}
                    {[<p key={signal.first_id + signal.second_id} className="details">{signal.first_id} ↔ {signal.second_id}: {signal.distance_meters} m · {signal.time_difference_hours} hours</p> for signal in decision.signals]}
                    <p className="muted"><DateTime value={decision.timestamp}/></p></article> for decision in state.decisions if decision.agent_run_id == item.id]}
                {len([decision for decision in state.decisions if decision.agent_run_id == item.id]) == 0 and <p className="muted">No candidate decisions recorded for this run.</p>}
            </details></div> for item in state.runs]}
        </section>}
        {activity and <section className="panel"><span className="badge planned">Not implemented yet</span><h3>Additional agents and human approval events</h3><p className="muted">Coordinator, response coordination, cleanup and volunteer agents are deferred.</p></section>}
    </div>
}
