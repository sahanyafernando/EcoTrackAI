import from ..navigation { workspace_navigation, page_title }
import from .Icon { Icon }

def:pub AppShell(context: str, page: str, display_name: str, context_name: str,
    busy: bool, onNavigate: Callable[[str], None], onLogout: Callable[[], None],
    onRefresh: Callable[[], None], children: any = None) -> JsxElement {
    has menuOpen: bool = False;
    def navigate(destination: str) {
        onNavigate(destination);
        menuOpen = False;
    }
    <div className="app-shell" onKeyDown={lambda (event: KeyboardEvent) { if event.key == "Escape" { menuOpen = False; } }}>
        <a className="skip-link" href="#page-content">Skip to content</a>
        {menuOpen and <button className="nav-overlay" aria-label="Close navigation" onClick={lambda { menuOpen = False; }}/>}
        <aside id="workspace-navigation" className={"sidebar open" if menuOpen else "sidebar"}>
            <button className="brand" onClick={lambda { navigate("overview"); }}><span className="brand-mark"><Icon name="leaf"/></span><span>EcoTrack <b>AI</b></span></button>
            <div className="workspace-label"><span className="eyebrow">Workspace</span><strong>{context_name}</strong></div>
            <nav aria-label="Workspace navigation">
                {[<button key={item.id} className={"nav-item active" if page == item.id else "nav-item"} aria-current={"page" if page == item.id else None} onClick={lambda { navigate(item.id); }}><Icon name={item.icon}/><span>{item.label}</span></button> for item in workspace_navigation(context)]}
            </nav>
            <div className="sidebar-bottom">
                <div className="sidebar-note"><Icon name="leaf"/><p>Small observations.<br/>Coordinated action.</p></div>
                <button className={"account-control active" if page == "profile" else "account-control"} onClick={lambda { navigate("profile"); }}>
                    <span className="avatar">{display_name[:1].upper()}</span><span><strong>{display_name}</strong><small>View profile</small></span>
                </button>
                <button className="logout-control" disabled={busy} onClick={onLogout}><Icon name="logout"/>Logout</button>
            </div>
        </aside>
        <div className="workspace-main">
            <header className="topbar">
                <div className="topbar-context"><button className="menu-toggle quiet" aria-label="Toggle navigation" aria-expanded={menuOpen} aria-controls="workspace-navigation" onClick={lambda { menuOpen = not menuOpen; }}><Icon name="menu"/></button><span className="muted">{context_name}</span><span className="breadcrumb-separator">/</span><strong>{page_title(context, page)}</strong></div>
                <button className="quiet refresh-control" disabled={busy} onClick={onRefresh}>Refresh</button>
            </header>
            <main id="page-content" tabIndex={-1} className="page-content">
                <div className="page-heading"><div><p className="eyebrow">EcoTrack workspace</p><h1>{page_title(context, page)}</h1></div><span className="workspace-pill">{context_name}</span></div>
                {children}
            </main>
            <footer className="workspace-footer">EcoTrack AI <span>Environmental observations. Shared responsibility.</span></footer>
        </div>
    </div>
}
