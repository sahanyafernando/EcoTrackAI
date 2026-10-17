import from .DateTime { DateTime }
import from endpoints { AccountView, OrganizationView }
import from .Icon { Icon }

def:pub ProfilePage(me: AccountView, context: str, onNavigate: Callable[[str], None]) -> JsxElement {
    <div>
        <section className="panel"><div className="profile-heading"><span className="avatar large">{me.display_name[:1].upper()}</span><div><h2>{me.display_name}</h2><span className="badge verified">{me.account_status}</span></div></div>
            <dl className="detail-grid"><div><dt>Workspace</dt><dd>{context}</dd></div><div><dt>Account created</dt><dd><DateTime value={me.created_at}/></dd></div><div><dt>Profile updated</dt><dd><DateTime value={me.updated_at}/></dd></div></dl>
            <details className="account-details"><summary>Advanced account details</summary><p className="muted">Account root for server-side authority configuration</p><code>{me.root_id}</code><p className="muted">Profile revision: {me.revision}</p></details>
        </section>
        <section className="panel"><h2>Personal reporting</h2><p className="muted">Your observations stay connected to your account in every workspace.</p><div className="button-row"><button onClick={lambda { onNavigate("report_issue"); }}>Report Issue <Icon name="arrow"/></button><button className="quiet" onClick={lambda { onNavigate("my_reports"); }}>My Reports</button></div></section>
        <section className="callout"><div><h3>{"Your organization" if me.organization is not None else "Represent an organization?"}</h3><p>{me.organization.name if me.organization is not None else "Submit an application for Central Authority verification."}</p></div><button className="quiet" onClick={lambda { onNavigate("organization"); }}>{"View organization" if me.organization is not None else "Apply as Organization"} →</button></section>
    </div>
}

def:pub AuditPage(items: list[OrganizationView], error: str, loading: bool) -> JsxElement {
    <div>
        <section className="panel"><h2>Latest organization decisions</h2><p className="muted">The most recent decision for each organization, from its current verification record.</p>
            {loading and <p role="status" className="muted">Loading organization decisions…</p>}
            {error != "" and <p role="alert" className="notice error">{error}</p>}
            {not loading and error == "" and len([org for org in items if org.reviewed_at != ""]) == 0 and <div className="empty-state">No organization decisions available.</div>}
            {[<article className="review-card" key={org.id}><div className="actions"><h3>{org.name}</h3><span className={"badge " + org.verification_status}>{org.verification_status}</span></div><p className="muted"><DateTime value={org.reviewed_at}/></p><details><summary>Reviewer reference</summary><code>{org.reviewed_by}</code></details></article> for org in items if org.reviewed_at != ""]}
        </section>
        <section className="callout"><div><span className="badge planned">Not implemented yet</span><h3>Full audit history</h3><p>A complete timeline of review records and governance actions will appear here.</p></div></section>
    </div>
}
