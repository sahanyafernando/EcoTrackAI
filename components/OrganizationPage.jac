import from .DateTime { DateTime }
import from endpoints { AccountView, OrganizationView }

def:pub OrganizationStatus(status: str) -> JsxElement {
    <div className={"organization-status " + status}>
        <span className={"badge " + status}>{status}</span>
        <h2>{"Verified Organization" if status == "verified" else ("Organization verification pending" if status == "pending" else ("Organization application rejected" if status == "rejected" else "Organization suspended"))}</h2>
        <p>{"Your organization has been verified by Central Authority. Incident coordination is not implemented yet." if status == "verified" else ("Official response functionality becomes available after Central Authority verification." if status == "pending" else ("Central Authority rejected this application. Your application details remain available below." if status == "rejected" else "Official response permissions are suspended. Your organization is not treated as verified."))}</p>
    </div>
}

def:pub OrganizationPage(me: AccountView, name: str, description: str, busy: bool,
    onName: Callable[[str], None], onDescription: Callable[[str], None], onSave: Callable[[FormEvent], None]) -> JsxElement {
    <div>
        {me.organization is not None and <OrganizationStatus status={me.organization.verification_status}/>}
        <section className="panel">
            <h2>{me.organization.name if me.organization is not None else "Apply as Organization"}</h2>
            {me.organization is None and <p className="muted">Represent an environmental organization? Submit an application for Central Authority verification.</p>}
            {me.organization is not None and <div>
                <p className="details">{me.organization.description}</p>
                <dl className="detail-grid"><div><dt>Submitted</dt><dd><DateTime value={me.organization.created_at}/></dd></div><div><dt>Last updated</dt><dd><DateTime value={me.organization.updated_at}/></dd></div></dl>
                {me.organization.reviewed_at != "" and <p className="muted">Latest review: <DateTime value={me.organization.reviewed_at}/></p>}
            </div>}
            {(me.organization is None or me.organization.verification_status == "pending") and <form onSubmit={onSave}>
                {me.organization is not None and <h3>Edit pending application</h3>}
                <label>Organization name<input required maxLength={160} disabled={busy} value={name} onChange={lambda (e: ChangeEvent) { onName(e.target.value); }}/></label>
                <label>Description<textarea required maxLength={3000} disabled={busy} value={description} onChange={lambda (e: ChangeEvent) { onDescription(e.target.value); }}/></label>
                <button disabled={busy} type="submit">{"Submit application" if me.organization is None else "Save application"}</button>
            </form>}
        </section>
    </div>
}

def:pub OrganizationReview(items: list[OrganizationView], root_id: str, busy: bool,
    error: str, loading: bool, onDecision: Callable[[OrganizationView, str], None]) -> JsxElement {
    <div>
        {loading and <p role="status" className="muted">Loading organizations…</p>}
        {error != "" and <p role="alert" className="notice error">{error}</p>}
        <section className="panel"><h2>Pending Organization Applications</h2><p className="muted">Review each application before granting verified status.</p>
            {not loading and error == "" and len([item for item in items if item.verification_status == "pending"]) == 0 and <div className="empty-state">No pending applications.</div>}
            {[<article className="review-card" key={org.id}>
                <div className="actions"><h3>{org.name}</h3><span className="badge pending">Pending</span></div>
                <p className="details">{org.description}</p><p className="muted">Applied <DateTime value={org.created_at}/></p>
                {org.created_by == root_id and <p className="muted">Your own organization requires review by another authority account.</p>}
                <div className="button-row"><button disabled={busy or org.created_by == root_id} onClick={lambda { onDecision(org, "verified"); }}>Verify</button><button className="danger-outline" disabled={busy or org.created_by == root_id} onClick={lambda { onDecision(org, "rejected"); }}>Reject</button></div>
            </article> for org in items if org.verification_status == "pending"]}
        </section>
        <section className="panel"><h2>Reviewed organizations</h2>
            {not loading and error == "" and len([item for item in items if item.verification_status != "pending"]) == 0 and <div className="empty-state">No reviewed organizations.</div>}
            {[<article className="review-card" key={org.id}>
                <div className="actions"><h3>{org.name}</h3><span className={"badge " + org.verification_status}>{org.verification_status}</span></div>
                <p className="details">{org.description}</p><p className="muted">Latest review: <DateTime value={org.reviewed_at}/></p>
                {org.verification_status == "verified" and <button className="danger-outline" disabled={busy or org.created_by == root_id} onClick={lambda { onDecision(org, "suspended"); }}>Suspend</button>}
            </article> for org in items if org.verification_status != "pending"]}
        </section>
    </div>
}
