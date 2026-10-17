"""Shared cleanup events page; all ownership and participation checks run in core."""
import type from contracts.cleanup_views { CleanupBoardView }
import type from contracts.cleanup_ai_views { CleanupPlanningView }
import from endpoints { cleanup_events, create_cleanup_event, manage_cleanup_event, join_cleanup, withdraw_cleanup, run_cleanup_ai, cleanup_ai_assessments }
import from .DateTime { DateTime }
import from .ReportCard { LocationLink }

def:pub CleanupAssessmentPanel(item: CleanupPlanningView) -> JsxElement {
    <article><h3>AI Volunteer Assessment</h3><p className="muted"><DateTime value={item.created_at}/> · {item.status}</p>
        {item.stale and <p className="notice">Event or volunteer state has changed. Run Cleanup AI again for a current assessment.</p>}
        {item.status == "failed" and <p className="notice error" role="alert">{item.error_summary} Category: {item.error_category}</p>}
        {item.status == "completed" and item.assessment is not None and not item.stale and <div>
            <p><strong>Risk: {item.assessment.risk_level.upper()}</strong> · {item.assessment.recommendation_type.replace("_", " ")}</p>
            <p>Required: {item.input_state.required_volunteers} · Joined: {item.input_state.joined_volunteers} · Missing: {item.assessment.volunteers_missing}</p>
            <p>{item.assessment.reasoning_summary}</p><ul>{[<li key={str(index)}>{action}</li> for (index, action) in enumerate(item.assessment.recommended_actions)]}</ul>
            <p className="muted">Advisory recommendation. No assignments, dates or participation have been changed.</p>
        </div>}
    </article>
}

def:pub CleanupPage() -> JsxElement {
    has board: CleanupBoardView | None = None, plans: list[CleanupPlanningView] = [], planError: str = "",
        planRequests: Ref[dict[str, str]] = Ref({}), loading: bool = True, busy: bool = False,
        error: str = "", feedback: str = "", incidentId: str = "", title: str = "",
        description: str = "", location: str = "", latitude: str = "", longitude: str = "",
        scheduledAt: str = "", required: str = "8", sending: Ref[bool] = Ref(False);
    can with entry { load(); }
    async def load -> None {
        loading = True; error = "";
        try {
            board = await cleanup_events();
            if incidentId == "" and len(board.lead_incidents) > 0 { incidentId = board.lead_incidents[0].incident_id; }
        } except Exception { error = "Cleanup events could not be loaded. Refresh and check your session."; }
        finally { loading = False; }
        try { plans = await cleanup_ai_assessments(); planError = ""; }
        except Exception { planError = "AI assessment history could not be loaded. Counts remain available; refresh to retry."; }
    }
    async def create(e: FormEvent) -> None {
        e.preventDefault();
        if sending.current { return; }
        sending.current = True; busy = True; feedback = "";
        try {
            result = await create_cleanup_event(incident_id=incidentId, title=title, description=description,
                location_text=location, latitude=Number(latitude), longitude=Number(longitude),
                scheduled_at=str(new(Date, scheduledAt).toISOString()), required_volunteers=int(required));
            feedback = "Cleanup event created: " + result.title;
            title = ""; description = ""; location = ""; incidentId = "";
            await load();
        } except Exception as failure { feedback = "Event was not created: " + str(failure); }
        finally { sending.current = False; busy = False; }
    }
    async def act(id: str, action: str, revision: int = 0) -> None {
        if sending.current { return; }
        sending.current = True; busy = True; feedback = "";
        try {
            if action == "join" { await join_cleanup(event_id=id); feedback = "You joined this cleanup."; }
            elif action == "withdraw" { await withdraw_cleanup(event_id=id); feedback = "Your participation was withdrawn."; }
            else { await manage_cleanup_event(event_id=id, status=action, expected_revision=revision); feedback = "Event status updated."; }
            await load();
        } except Exception as failure { feedback = "Operation was not completed: " + str(failure); await load(); }
        finally { sending.current = False; busy = False; }
    }
    async def plan(id: str) -> None {
        if sending.current { return; }
        sending.current = True; busy = True; feedback = "";
        if id not in planRequests.current { planRequests.current[id] = str(globalThis.crypto.randomUUID()); }
        try {
            result = await run_cleanup_ai(event_id=id, request_id=planRequests.current[id]);
            if result.status != "running" { del planRequests.current[id]; }
            feedback = result.error_summary if result.status == "failed" else ("AI assessment recorded." if result.status == "completed" else "The previous run is still marked running. Ask Central Authority to inspect Agent Activity before retrying.");
            await load();
        } except Exception as failure { feedback = "Cleanup AI was not completed. Retry uses the same request ID. " + str(failure); }
        finally { sending.current = False; busy = False; }
    }
    <div>
        <section className="panel"><div className="actions"><div><p className="eyebrow">Community action</p><h2>Cleanup Events</h2><p>Join a real organization-led cleanup. Participation is linked to your current account.</p></div><button className="quiet" onClick={load} disabled={busy or loading}>Refresh events</button></div>
            {loading and <p role="status">Loading events…</p>}
            {error != "" and <p className="notice error" role="alert">{error}</p>}
            {planError != "" and <p className="notice" role="status">{planError}</p>}
            {feedback != "" and <p className="notice" role="status" aria-live="polite">{feedback}</p>}
        </section>
        {board is not None and error == "" and len(board.lead_incidents) > 0 and <section className="panel"><h2>Create Cleanup Event</h2><p className="muted">Available only for Incidents where your verified organization is the active Lead. Enter the meeting location; no coordinates are assumed.</p>
            <form onSubmit={create}>
                <label>Lead Incident<select required value={incidentId} disabled={busy} onChange={lambda (e: ChangeEvent) { incidentId = e.target.value; }}>
                    {[<option key={item.incident_id} value={item.incident_id}>{item.category.replace("_", " ")} · {item.incident_id}</option> for item in board.lead_incidents]}
                </select></label>
                <label>Title<input required maxLength={160} value={title} disabled={busy} onChange={lambda (e: ChangeEvent) { title = e.target.value; }}/></label>
                <label>Description<textarea required maxLength={3000} value={description} disabled={busy} onChange={lambda (e: ChangeEvent) { description = e.target.value; }}/></label>
                <label>Meeting location<input required maxLength={500} value={location} disabled={busy} onChange={lambda (e: ChangeEvent) { location = e.target.value; }}/></label>
                <label>Latitude<input required type="number" step="any" min="-90" max="90" value={latitude} disabled={busy} onChange={lambda (e: ChangeEvent) { latitude = e.target.value; }}/></label>
                <label>Longitude<input required type="number" step="any" min="-180" max="180" value={longitude} disabled={busy} onChange={lambda (e: ChangeEvent) { longitude = e.target.value; }}/></label>
                <label>Scheduled date and time (your local timezone)<input required type="datetime-local" value={scheduledAt} disabled={busy} onChange={lambda (e: ChangeEvent) { scheduledAt = e.target.value; }}/></label>
                <label>Required volunteers<input required type="number" min="1" max="1000" step="1" value={required} disabled={busy} onChange={lambda (e: ChangeEvent) { required = e.target.value; }}/></label>
                <button type="submit" disabled={busy or loading}>{"Saving…" if busy else "Create Cleanup Event"}</button>
            </form>
        </section>}
        {board is not None and error == "" and len(board.events) == 0 and <section className="panel empty-state"><h3>No cleanup events yet</h3><p>Official events will appear after a verified Lead organization creates one.</p></section>}
        {board is not None and error == "" and [<section className="panel" key={item.event_id}>
            <div className="actions"><h2>{item.title}</h2><span className={"badge " + ("rejected" if item.status == "cancelled" else "verified")}>{item.status}</span></div>
            <p className="details">{item.description}</p><p>Organized by {item.organization_name} · {item.category.replace("_", " ")}</p>
            <p>{item.location_text} · {item.latitude}, {item.longitude}</p><LocationLink latitude={item.latitude} longitude={item.longitude}/>
            <p>Scheduled: <DateTime value={item.scheduled_at}/></p>
            <div className="button-row"><strong>Required: {item.required_volunteers}</strong><strong>Joined: {item.joined_volunteers}</strong><strong>Remaining needed: {item.remaining_needed}</strong></div>
            <p>Your participation: {item.my_participation}</p>
            <div className="button-row">
                {item.my_participation != "joined" and item.status in ["planned", "active"] and <button disabled={busy or loading} onClick={lambda { act(item.event_id, "join"); }}>Join Cleanup</button>}
                {item.my_participation == "joined" and <button className="quiet" disabled={busy or loading} onClick={lambda { act(item.event_id, "withdraw"); }}>Withdraw</button>}
                {item.can_manage and item.status == "planned" and <button className="quiet" disabled={busy or loading} onClick={lambda { act(item.event_id, "active", item.revision); }}>Start event</button>}
                {item.can_manage and item.status == "active" and <button className="quiet" disabled={busy or loading} onClick={lambda { act(item.event_id, "completed", item.revision); }}>Complete event</button>}
                {item.can_manage and item.status in ["planned", "active"] and <button className="danger-outline" disabled={busy or loading} onClick={lambda { act(item.event_id, "cancelled", item.revision); }}>Cancel event</button>}
                {item.can_manage and item.status in ["planned", "active"] and <button disabled={busy or loading} onClick={lambda { plan(item.event_id); }}>{"Request in progress…" if busy else "Run Cleanup AI"}</button>}
            </div><p className="details muted">Event {item.event_id} · Incident {item.incident_id}</p>
            {[<CleanupAssessmentPanel key={assessment.run_id} item={assessment}/> for assessment in plans if assessment.event_id == item.event_id]}
        </section> for item in board.events]}
    </div>
}
