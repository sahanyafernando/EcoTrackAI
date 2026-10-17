"""Minimal EcoTrack shell using the Jac runtime's managed auth session."""
import from "@jac/runtime" { SignupResult, jacLogin, jacSignup, jacLogout, jacIsLoggedIn }
import from endpoints { AccountView, OrganizationView, account, apply, edit_organization, organizations, review }

def:pub app -> JsxElement {
    has me: AccountView | None = None,
        items: list[OrganizationView] = [],
        username: str = "",
        password: str = "",
        displayName: str = "",
        registering: bool = False,
        busy: bool = False,
        recovering: bool = True,
        message: str = "",
        orgName: str = "",
        description: str = "";

    can with entry { recover(); }
    async def recover -> None;
    async def load(display_name: str = "") -> None;
    async def authenticate(e: FormEvent) -> None;
    def logout -> None;
    async def saveOrganization(e: FormEvent) -> None;
    async def decide(org: OrganizationView, decision: str) -> None;
    async def refresh -> None;

    <main style={{"maxWidth": "960px", "margin": "2rem auto", "padding": "0 1rem", "fontFamily": "system-ui, sans-serif", "color": "#173d34"}}>

        <style>{"""
body { margin: 0; background: #f3f7f4; }
            header, .actions { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
            section, article { background: white; border: 1px solid #d6e5dd; border-radius: 12px; padding: 20px; margin: 18px 0; }
            form { display: grid; gap: 12px; max-width: 560px; }
            label { display: grid; gap: 5px; font-weight: 600; }
            input, textarea, button { font: inherit; padding: 10px 12px; border: 1px solid #aac5b8; border-radius: 6px; box-sizing: border-box; }
            input, textarea { width: 100%; min-width: 0; }
            textarea { min-height: 110px; resize: vertical; }
            button { cursor: pointer; background: #1d654c; color: white; }
            button:disabled { opacity: .6; cursor: wait; }
            .badge { display: inline-block; padding: 5px 10px; border-radius: 20px; background: #e5f0e9; text-transform: capitalize; }
            .muted { color: #536c61; } .details { white-space: pre-wrap; overflow-wrap: anywhere; }
            code { overflow-wrap: anywhere; } h1 { margin-bottom: 4px; } button:focus-visible, input:focus-visible, textarea:focus-visible { outline: 3px solid #d6a628; }
"""}</style>
        <header>
            <div><h1>EcoTrack AI</h1><p className="muted">Environmental coordination starts with trusted organizations.</p></div>
            {me is not None and <button onClick={logout} disabled={busy}>Logout</button>}
        </header>
        <p role="status" aria-live="polite">{message}</p>
        {recovering and <p>Recovering your session…</p>}
        {not recovering and me is None and <section>
            <h2>{"Register" if registering else "Login"}</h2>
            <p>Use your Jac username to access EcoTrack.</p>
            <form onSubmit={authenticate}>
                <label>Username<input required autoComplete="username" value={username} onChange={lambda (e: ChangeEvent) { username = e.target.value; }}/></label>
                {registering and <label>Display name<input required maxLength={100} autoComplete="name" value={displayName} onChange={lambda (e: ChangeEvent) { displayName = e.target.value; }}/></label>}
                <label>Password<input required type="password" autoComplete={"new-password" if registering else "current-password"} value={password} onChange={lambda (e: ChangeEvent) { password = e.target.value; }}/></label>
                <button type="submit" disabled={busy}>{"Please wait…" if busy else ("Register" if registering else "Login")}</button>
                <button type="button" disabled={busy} onClick={lambda { registering = not registering; message = ""; }}>{"Already registered? Login" if registering else "Create an account"}</button>
            </form>
        </section>}
        {me is not None and <div>
            <section>
                <div className="actions"><h2>{"Authority dashboard" if "organization:verify" in me.capabilities else "Your dashboard"}</h2><button onClick={refresh} disabled={busy}>Refresh</button></div>
                <p>Welcome, {me.display_name}. <span className="badge">{me.account_status}</span></p>
                <p>{"Central Authority" if "organization:verify" in me.capabilities else ("Organization admin" if me.organization is not None else "Citizen")}</p>
                <p className="muted">Account root: <code>{me.root_id}</code></p>
            </section>
            <section>
                <h2>Organization</h2>
                {me.organization is not None and <div>
                    <h3>{me.organization.name}</h3>
                    <span className="badge">{me.organization.verification_status}</span>
                    <p className="details">{me.organization.description}</p>
                    {me.organization.reviewed_at != "" and <p className="muted">Reviewed {me.organization.reviewed_at}</p>}
                    {me.organization.verification_status == "pending" and <p className="muted">Your application is awaiting Central Authority review.</p>}
                    {me.organization.verification_status == "verified" and <p>Your organization is verified.</p>}
                </div>}
                {(me.organization is None or me.organization.verification_status == "pending") and <form onSubmit={saveOrganization}>
                    <h3>{"Apply as Organization" if me.organization is None else "Edit pending application"}</h3>
                    <label>Organization name<input required maxLength={160} value={orgName} onChange={lambda (e: ChangeEvent) { orgName = e.target.value; }}/></label>
                    <label>Description<textarea required maxLength={3000} value={description} onChange={lambda (e: ChangeEvent) { description = e.target.value; }}/></label>
                    <button disabled={busy} type="submit">{"Submit application" if me.organization is None else "Save application"}</button>
                </form>}
            </section>
            {"organization:verify" in me.capabilities and <section>
                <h2>Pending Organization Applications</h2>
                {len([item for item in items if item.verification_status == "pending"]) == 0 and <p>No pending applications.</p>}
                {[
                    <article key={org.id}>
                        <h3>{org.name}</h3><span className="badge">{org.verification_status}</span>
                        <p className="details">{org.description}</p><p className="muted">Applied {org.created_at}</p>
                        <div className="actions">
                            <button disabled={busy or org.created_by == me.root_id} onClick={lambda { decide(org, "verified"); }}>Verify</button>
                            <button disabled={busy or org.created_by == me.root_id} onClick={lambda { decide(org, "rejected"); }}>Reject</button>
                        </div>
                    </article> for org in items if org.verification_status == "pending"
                ]}
                <h2>Reviewed organizations</h2>
                {len([item for item in items if item.verification_status != "pending"]) == 0 and <p>No reviewed organizations.</p>}
                {[
                    <article key={org.id}>
                        <h3>{org.name}</h3><span className="badge">{org.verification_status}</span>
                        <p className="details">{org.description}</p>
                        <p className="muted">Reviewed {org.reviewed_at} by <code>{org.reviewed_by}</code></p>
                        {org.verification_status == "verified" and <button disabled={busy or org.created_by == me.root_id} onClick={lambda { decide(org, "suspended"); }}>Suspend</button>}
                    </article> for org in items if org.verification_status != "pending"
                ]}
            </section>}
        </div>}
    </main>
}
