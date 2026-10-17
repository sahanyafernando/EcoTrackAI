"""One authenticated shell; role and pages come from the server account view."""
import type from contracts.report_views { ReportView }
import from "@jac/runtime" { SignupResult, jacLogin, jacSignup, jacLogout, jacIsLoggedIn }
import from endpoints { AccountView, OrganizationView, account, apply, edit_organization, organizations, review, my_reports, all_reports }
import from .navigation { workspace_context, resolve_page }
import from .components.AppTheme { AppTheme }
import from .components.AppShell { AppShell }
import from .components.AuthPage { AuthPage }
import from .components.Icon { Icon }
import from .components.OverviewPages { CitizenOverview, OrganizationOverview, AuthorityOverview }
import from .components.OrganizationPage { OrganizationPage, OrganizationReview }
import from .components.AccountPages { ProfilePage, AuditPage }
import from .components.ReportPanel { ReportPanel }
import from .components.ReportListPage { ReportListPage }
import from .components.PlannedPage { PlannedPage }
import from .components.IntelligencePage { IntelligencePage }
import from .components.ResponseBoard { ResponseBoard }

def:pub app -> JsxElement {
    has me: AccountView | None = None,
        items: list[OrganizationView] = [],
        ownReports: list[ReportView] = [],
        incomingReports: list[ReportView] = [],
        page: str = "overview",
        username: str = "",
        password: str = "",
        displayName: str = "",
        registering: bool = False,
        busy: bool = False,
        dataLoading: bool = True,
        recovering: bool = True,
        message: str = "",
        organizationError: str = "",
        ownReportsError: str = "",
        incomingError: str = "",
        orgName: str = "",
        description: str = "";

    can with entry { recover(); }
    async def recover -> None;
    async def load(display_name: str = "") -> None;
    async def authenticate(e: FormEvent) -> None;
    def logout -> None;
    def navigate(destination: str) -> None;
    def reportSaved(item: ReportView) -> None;
    async def saveOrganization(e: FormEvent) -> None;
    async def decide(org: OrganizationView, decision: str) -> None;
    async def refresh -> None;

    context = workspace_context(me.capabilities, me.organization is not None) if me is not None else "citizen";
    activePage = resolve_page(context, page);
    contextName = "Central Authority" if context == "authority" else ("Organization workspace" if context == "organization" else "Citizen workspace");

    <div>
        <AppTheme/>
        {recovering and <main className="recovery-page"><div><span className="brand-mark"><Icon name="leaf"/></span><h2>EcoTrack AI</h2><p role="status">Recovering your session…</p></div></main>}
        {not recovering and me is None and <AuthPage username={username} password={password} display_name={displayName} registering={registering} busy={busy} message={message} onUsername={lambda (value: str) { username = value; }} onPassword={lambda (value: str) { password = value; }} onDisplayName={lambda (value: str) { displayName = value; }} onToggle={lambda { registering = not registering; message = ""; }} onSubmit={authenticate}/>}
        {not recovering and me is not None and <AppShell context={context} page={activePage} display_name={me.display_name} context_name={contextName} busy={busy} onNavigate={navigate} onLogout={logout} onRefresh={refresh}>
            {message != "" and <p role="status" aria-live="polite" className="notice">{message}</p>}
            {activePage == "overview" and context == "citizen" and <CitizenOverview me={me} reports={ownReports} loading={dataLoading} error={ownReportsError} onNavigate={navigate}/>}
            {activePage == "overview" and context == "organization" and <OrganizationOverview me={me} onNavigate={navigate}/>}
            {activePage == "overview" and context == "authority" and <AuthorityOverview organizations={items} reports={incomingReports} loading={dataLoading} organization_error={organizationError} report_error={incomingError} onNavigate={navigate}/>}
            {"report:create" in me.capabilities and <div hidden={activePage != "report_issue"}>
                <ReportPanel key={me.root_id} onSaved={reportSaved}/>
                <button className="quiet page-shortcut" onClick={lambda { navigate("my_reports"); }}>View My Reports →</button>
            </div>}
            {activePage == "my_reports" and <ReportListPage incoming={False} items={ownReports} loading={dataLoading} error={ownReportsError} onRefresh={refresh}/>}
            {activePage == "incoming" and context == "authority" and <ReportListPage incoming={True} items={incomingReports} loading={dataLoading} error={incomingError} onRefresh={refresh}/>}
            {activePage == "organization" and <OrganizationPage me={me} name={orgName} description={description} busy={busy} onName={lambda (value: str) { orgName = value; }} onDescription={lambda (value: str) { description = value; }} onSave={saveOrganization}/>}
            {activePage == "review" and context == "authority" and <OrganizationReview items={items} root_id={me.root_id} busy={busy} error={organizationError} loading={dataLoading} onDecision={decide}/>}
            {activePage == "profile" and <ProfilePage me={me} context={contextName} onNavigate={navigate}/>}
            {activePage == "audit" and context == "authority" and <AuditPage items={items} error={organizationError} loading={dataLoading}/>}
            {activePage == "cleanups" and <PlannedPage title="Cleanup Events" description={"This page will allow citizens to discover and join environmental cleanup events." if context == "citizen" else "Organizations will use this page to plan and manage environmental cleanup events."}/>}
            {activePage == "incidents" and context == "organization" and <ResponseBoard key={me.root_id}/>}
            {activePage == "volunteers" and context == "organization" and <PlannedPage title="Volunteers" icon="people" description="Organizations will use this page to coordinate volunteer participation and readiness for cleanup events."/>}
            {activePage == "incident_review" and context == "authority" and <IntelligencePage key={me.root_id + "review"} onDemoChanged={refresh}/>}
            {activePage == "agents" and context == "authority" and <IntelligencePage key={me.root_id + "activity"} activity={True}/>}
        </AppShell>}
    </div>
}
