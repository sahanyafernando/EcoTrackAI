import from .Icon { Icon }

def:pub AuthPage(username: str, password: str, display_name: str, registering: bool,
    busy: bool, message: str, onUsername: Callable[[str], None], onPassword: Callable[[str], None],
    onDisplayName: Callable[[str], None], onToggle: Callable[[], None],
    onSubmit: Callable[[FormEvent], None]) -> JsxElement {
    <main className="auth-page">
        <div className="auth-story">
            <div className="brand"><span className="brand-mark"><Icon name="leaf"/></span><span>EcoTrack <b>AI</b></span></div>
            <div className="auth-story-content"><p className="eyebrow">Agentic Environmental Coordination</p><h1>A clearer picture.<br/>A cleaner tomorrow.</h1><p>Turn environmental observations into the starting point for coordinated community action.</p></div>
            <div className="auth-leaf"><Icon name="leaf"/></div><p className="auth-story-footer">Observe your surroundings. Help your community.</p>
        </div>
        <div className="auth-form-wrap"><div className="auth-card">
            <div className="brand auth-mobile-brand"><span className="brand-mark"><Icon name="leaf"/></span><span>EcoTrack <b>AI</b></span></div>
            <p className="eyebrow">Agentic Environmental Coordination</p>
            <h2>{"Join your community." if registering else "Welcome back."}</h2><p>{"Create your EcoTrack account to get started." if registering else "Login to your EcoTrack workspace."}</p>
            <form onSubmit={onSubmit}>
                <label>Username<input required disabled={busy} autoComplete="username" value={username} onChange={lambda (e: ChangeEvent) { onUsername(e.target.value); }}/></label>
                {registering and <label>Display name<input required maxLength={100} disabled={busy} autoComplete="name" value={display_name} onChange={lambda (e: ChangeEvent) { onDisplayName(e.target.value); }}/></label>}
                <label>Password<input required disabled={busy} type="password" autoComplete={"new-password" if registering else "current-password"} value={password} onChange={lambda (e: ChangeEvent) { onPassword(e.target.value); }}/></label>
                <button type="submit" disabled={busy}>{"Please wait…" if busy else ("Register" if registering else "Login")}<Icon name="arrow"/></button>
            </form>
            <button className="auth-switch" type="button" disabled={busy} onClick={onToggle}>{"Already registered? Login" if registering else "Create an account"}</button>
            {message != "" and <p role="status" aria-live="polite" className="notice">{message}</p>}
        </div></div>
    </main>
}
