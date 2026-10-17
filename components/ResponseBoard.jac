"""Shared response view; authority actions remain protected by server capabilities."""
import type from contracts.response_views { ResponseBoardView }
import from endpoints { incident_response_board, coordinate_response, accept_response, coordinate_workflow }

def:pub ResponseBoard() -> JsxElement {
    has board: ResponseBoardView | None = None, loading: bool = True, busy: bool = False,
        feedback: str = "", error: str = "", sending: Ref[bool] = Ref(False),
        requestIds: Ref[dict[str, str]] = Ref({});
    can with entry { load(); }
    async def load -> None {
        loading = True; error = "";
        try { board = await incident_response_board(); }
        except Exception { error = "Response information could not be loaded. Refresh and check your current permissions."; }
        finally { loading = False; }
    }
    def organizationName(id: str) -> str {
        if board is not None {
            for org in board.organizations { if org.id == id { return org.name; } }
        }
        return id;
    }
    async def coordinate(id: str) -> None {
        if sending.current { return; }
        sending.current = True; busy = True; feedback = "";
        if id not in requestIds.current { requestIds.current[id] = str(globalThis.crypto.randomUUID()); }
        try {
            result = await coordinate_response(incident_id=id, request_id=requestIds.current[id]);
            del requestIds.current[id];
            feedback = result.error_summary if result.status == "failed" else result.summary;
            await load();
        } except Exception { feedback = "Coordination could not complete. Refresh Agent Activity before retrying; the same request ID will be reused."; }
        finally { sending.current = False; busy = False; }
    }
    async def orchestrate(id: str) -> None {
        if sending.current { return; }
        sending.current = True; busy = True; feedback = "";
        key = "coordinator:" + id;
        if key not in requestIds.current { requestIds.current[key] = str(globalThis.crypto.randomUUID()); }
        try {
            result = await coordinate_workflow(event_type="incident_confirmed", entity_id=id, request_id=requestIds.current[key]);
            if result.status != "running" { del requestIds.current[key]; }
            feedback = result.error_summary if result.status == "failed" else "Coordinator: " + result.summary + " See Agent Activity for the handoff.";
            await load();
        } except Exception { feedback = "Coordinator request failed. Check Agent Activity before retrying; the request ID is retained."; }
        finally { sending.current = False; busy = False; }
    }
    async def assign(id: str, org: str, role: str, revision: int, run: str) -> None {
        if sending.current { return; }
        sending.current = True; busy = True; feedback = "";
        try {
            result = await accept_response(incident_id=id, organization_id=org, role=role,
                expected_revision=revision, run_id=run);
            feedback = result.organization_name + " assigned as " + result.role + ".";
            await load();
        } except Exception as failure {
            feedback = "Assignment refused. Refresh and check current lead, eligibility and recommendation. " + str(failure);
            await load();
        } finally { sending.current = False; busy = False; }
    }
    <section className="panel"><div className="actions"><div><p className="eyebrow">One lead · Shared response</p><h2>Response Coordination</h2></div><button className="quiet" disabled={loading or busy} onClick={load}>Refresh responses</button></div>
        {loading and <p role="status">Loading responses…</p>}
        {busy and <p role="status">Processing response coordination…</p>}
        {error != "" and <p className="notice error" role="alert">{error}</p>}
        {feedback != "" and <p className="notice" role="status">{feedback}</p>}
        {board is not None and not board.authority and board.organization_status != "verified" and <div className="empty-state"><h3>Verified organizations only</h3><p>Your organization is {board.organization_status}. Response access requires Central Authority verification.</p></div>}
        {board is not None and error == "" and (board.authority or board.organization_status == "verified") and len(board.incidents) == 0 and <p className="muted">No confirmed Incidents are available yet.</p>}
        {board is not None and error == "" and [<article key={item.incident_id}>
            <div className="actions"><h3>{item.category.replace("_", " ")}</h3><span className="badge verified">{item.status}</span></div>
            <p className="details">Incident {item.incident_id}</p><p>Severity: {item.severity} · {item.report_count} source reports</p>
            <p><strong>Lead: </strong>{item.lead.organization_name if item.lead is not None else "Unassigned"}</p>
            {item.lead is not None and <p className="notice">Lead response already assigned. Join as Support through Central Authority.</p>}
            <p><strong>Support: </strong>{", ".join([support.organization_name for support in item.supports]) if len(item.supports) > 0 else "None assigned"}</p>
            {not board.authority and <p>Your organization: <span className="badge">{item.own_role}</span></p>}
            {board.authority and <div><button disabled={busy or loading} onClick={lambda { coordinate(item.incident_id); }}>Run Response Coordination</button><button className="quiet" disabled={busy or loading} onClick={lambda { orchestrate(item.incident_id); }}>Run Coordinator</button>
                {[<div key={recommendation.run_id}><p className="details">{recommendation.reasoning_summary}</p>
                    {recommendation.lead_organization_id != "" and <div className="actions"><p>Recommended Lead: {organizationName(recommendation.lead_organization_id)}</p><button disabled={busy or loading or item.lead is not None} onClick={lambda { assign(item.incident_id, recommendation.lead_organization_id, "lead", item.revision, recommendation.run_id); }}>Accept Lead</button></div>}
                    {[<div key={id} className="actions"><p>Recommended Support: {organizationName(id)}</p><button className="quiet" disabled={busy or loading or any([support.organization_id == id for support in item.supports])} onClick={lambda { assign(item.incident_id, id, "support", item.revision, recommendation.run_id); }}>Add Support</button></div> for id in recommendation.support_organization_ids]}
                </div> for recommendation in item.recommendations]}
            </div>}
        </article> for item in board.incidents]}
    </section>
}
