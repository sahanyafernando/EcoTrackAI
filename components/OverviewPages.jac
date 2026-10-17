import from .DateTime { DateTime }
import from endpoints { AccountView, OrganizationView, ReportView }
import from .ReportCard { ReportCard }
import from .OrganizationPage { OrganizationStatus }
import from .Icon { Icon }

def:pub CitizenOverview(me: AccountView, reports: list[ReportView], loading: bool,
    error: str, onNavigate: Callable[[str], None]) -> JsxElement {
    <div>
        <section className="welcome-card"><div><p className="eyebrow">Your community, your observations</p><h2>Welcome, {me.display_name}.</h2><p>Help make environmental issues visible.<br/>Share what you see, wherever you are.</p><button onClick={lambda { onNavigate("report_issue"); }}>Report Environmental Issue <Icon name="arrow"/></button></div><div className="hero-leaf"><Icon name="leaf"/></div></section>
        <div className="metric-grid">
            <section className="metric"><span className="metric-icon"><Icon name="reports"/></span><p>Your reports</p><strong>{"…" if loading else ("Unavailable" if error else str(len(reports)))}</strong><small>Observations you have submitted</small></section>
            <section className="metric"><span className="metric-icon"><Icon name="pin"/></span><p>Submitted reports</p><strong>{"…" if loading else ("Unavailable" if error else str(len([item for item in reports if item.status == "submitted"])))}</strong><small>Saved for Central Authority review</small></section>
        </div>
        <section className="panel"><div className="actions"><h2>Recent reports</h2><button className="quiet" onClick={lambda { onNavigate("my_reports"); }}>View all reports →</button></div>
            {loading and <p className="muted">Loading your reports…</p>}
            {error != "" and <p role="alert" className="notice error">{error}</p>}
            {not loading and error == "" and len(reports) == 0 and <div className="empty-state"><Icon name="reports"/><h3>Your first observation starts here</h3><p>Your submitted environmental reports will appear here.</p><button className="quiet" onClick={lambda { onNavigate("report_issue"); }}>Report an issue</button></div>}
            {[<ReportCard key={item.id} item={item}/> for item in reports[:3]]}
        </section>
        <section className="callout"><div><h3>Represent an environmental organization?</h3><p>Apply for verification to prepare for coordinated response.</p></div><button className="quiet" onClick={lambda { onNavigate("organization"); }}>Apply as Organization →</button></section>
    </div>
}

def:pub OrganizationOverview(me: AccountView, onNavigate: Callable[[str], None]) -> JsxElement {
    <div>
        {me.organization is not None and <div>
            <section className="welcome-card compact"><div><p className="eyebrow">Organization workspace</p><h2>{me.organization.name}</h2><p>Manage your application and organization details.</p><button onClick={lambda { onNavigate("organization"); }}>View organization <Icon name="arrow"/></button></div><div className="hero-leaf"><Icon name="organization"/></div></section>
            <OrganizationStatus status={me.organization.verification_status}/>
            <section className="panel"><h2>Organization at a glance</h2><dl className="detail-grid"><div><dt>Membership</dt><dd>{"Organization admin" if me.organization.created_by == me.root_id else "Organization member"}</dd></div><div><dt>Application status</dt><dd><span className={"badge " + me.organization.verification_status}>{me.organization.verification_status}</span></dd></div><div><dt>Submitted</dt><dd><DateTime value={me.organization.created_at}/></dd></div></dl></section>
            <section className="panel"><span className="badge planned">Not implemented yet</span><h2>Coordinated response</h2><p className="muted">Incident coordination, cleanup events and volunteer management will appear in their dedicated pages as they become available.</p></section>
        </div>}
    </div>
}

def:pub AuthorityOverview(organizations: list[OrganizationView], reports: list[ReportView],
    loading: bool, organization_error: str, report_error: str,
    onNavigate: Callable[[str], None]) -> JsxElement {
    <div>
        <section className="welcome-card authority"><div><p className="eyebrow">Central Authority</p><h2>Clarity before coordination.</h2><p>Review incoming observations and verify the organizations<br/>preparing to act on environmental issues.</p><div className="button-row"><button onClick={lambda { onNavigate("review"); }}>Review Organizations <Icon name="arrow"/></button><button className="quiet" onClick={lambda { onNavigate("incoming"); }}>View Incoming Reports</button></div></div><div className="hero-leaf"><Icon name="audit"/></div></section>
        <div className="metric-grid three">
            <section className="metric"><span className="metric-icon"><Icon name="organization"/></span><p>Pending applications</p><strong>{"…" if loading else ("Unavailable" if organization_error else str(len([item for item in organizations if item.verification_status == "pending"])))}</strong><small>Awaiting organization verification</small></section>
            <section className="metric"><span className="metric-icon"><Icon name="reports"/></span><p>Incoming reports</p><strong>{"…" if loading else ("Unavailable" if report_error else str(len(reports)))}</strong><small>Citizen environmental observations</small></section>
            <section className="metric"><span className="metric-icon"><Icon name="audit"/></span><p>Verified organizations</p><strong>{"…" if loading else ("Unavailable" if organization_error else str(len([item for item in organizations if item.verification_status == "verified"])))}</strong><small>Current verified status only</small></section>
        </div>
        {organization_error != "" and <p role="alert" className="notice error">{organization_error}</p>}
        {report_error != "" and <p role="alert" className="notice error">{report_error}</p>}
        <div className="overview-links"><button className="action-card" onClick={lambda { onNavigate("review"); }}><Icon name="organization"/><strong>Organization Review</strong><span>Inspect applications and manage verification.</span><Icon name="arrow"/></button><button className="action-card" onClick={lambda { onNavigate("incoming"); }}><Icon name="reports"/><strong>Incoming Reports</strong><span>Read citizen observations and their locations.</span><Icon name="arrow"/></button></div>
    </div>
}
