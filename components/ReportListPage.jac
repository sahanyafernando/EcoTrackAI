import from endpoints { ReportView }
import from .ReportCard { ReportCard }
import from .Icon { Icon }

def:pub ReportListPage(incoming: bool, items: list[ReportView], loading: bool,
    error: str, onRefresh: Callable[[], None]) -> JsxElement {
    <section className="panel">
        <div className="actions"><div><h2>{"Citizen observations" if incoming else "Your environmental observations"}</h2><p className="muted">{"Raw citizen reports available to Central Authority." if incoming else "Your reports are visible to you and Central Authority."}</p></div><button className="quiet" onClick={onRefresh} disabled={loading}>Refresh reports</button></div>
        {loading and <p role="status">Loading reports…</p>}
        {error != "" and <p role="alert" className="notice error">{error}</p>}
        {not loading and error == "" and len(items) == 0 and <div className="empty-state"><Icon name="reports"/><h3>{"No incoming reports." if incoming else "No reports submitted yet."}</h3><p>{"New citizen observations will appear here." if incoming else "Use Report Issue to share your first observation."}</p></div>}
        {[<ReportCard key={item.id} item={item}/> for item in items]}
    </section>
}
