"""Shared citizen/authority presentation without reporter personal data."""
import type from contracts.report_views { ReportView }
import from .DateTime { DateTime }

def:pub LocationLink(latitude: float, longitude: float) -> JsxElement {
    <a href={"https://www.openstreetmap.org/?mlat=" + str(latitude) + "&mlon=" + str(longitude) + "#map=16/" + str(latitude) + "/" + str(longitude)} target="_blank" rel="noopener noreferrer">
        View position on OpenStreetMap ↗
    </a>
}

def:pub ReportCard(item: ReportView) -> JsxElement {
    <article>
        <h3>{item.category.replace("_", " ")}</h3>
        <p>{item.source_type == "demo_seed" and <span className="badge planned">Demo</span>} Report <code>{item.id}</code> <span className="badge">{item.status}</span></p>
        <p className="details">{item.description[:240]}</p>
        {len(item.description) > 240 and <details><summary>Full description</summary><p className="details">{item.description}</p></details>}
        <p className="details">{item.location_text}</p>
        <p>Latitude: {item.latitude} · Longitude: {item.longitude}</p>
        <LocationLink latitude={item.latitude} longitude={item.longitude}/>
        <p className="muted">Submitted: <DateTime value={item.submitted_at}/></p>
    </article>
}
