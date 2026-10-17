"""Jac-native report form and one-shot browser GPS capture."""
import from endpoints { ReportView, report_categories, create_report }
import from .ReportCard { LocationLink }

def:pub ReportPanel(onSaved: Callable[[ReportView], None]) -> JsxElement {
    has categories: list[str] = [],
        description: str = "",
        category: str = "",
        latitude: str = "",
        longitude: str = "",
        locationText: str = "",
        confirmed: bool = False,
        locating: bool = False,
        saving: bool = False,
        loading: bool = True,
        feedback: str = "",
        locationMessage: str = "",
        sendingRef: Ref[bool] = Ref(False),
        requestRef: Ref[str] = Ref(""),
        gpsGeneration: Ref[int] = Ref(0);

    can with entry { loadReports(); }
    can with exit { gpsGeneration.current = -1; }
    async def loadReports -> None;
    async def submit(e: FormEvent) -> None;
    def locate -> None;
    def confirmLocation -> None;
    def changeLocation -> None;

    <div>
        <section className="panel" aria-labelledby="report-form-title">
            <h2 id="report-form-title">Report an environmental issue</h2>
            <p>Describe one observation. Your report is visible to you and Central Authority.</p>
            <form onSubmit={submit}>
                <label>Report description<textarea required maxLength={5000} disabled={saving} value={description} onChange={lambda (e: ChangeEvent) { description = e.target.value; }}/></label>
                <label>Category<select required disabled={saving or len(categories) == 0} value={category} onChange={lambda (e: ChangeEvent) { category = e.target.value; }}>
                    <option value="">Choose a category</option>
                    {[<option key={value} value={value}>{value.replace("_", " ")}</option> for value in categories]}
                </select></label>
                <button type="button" onClick={locate} disabled={locating or confirmed or saving}>{"Acquiring location…" if locating else "Use my current location"}</button>
                <p role="status" aria-live="polite">{locationMessage}</p>
                <p className="muted">You can enter coordinates manually if GPS is unavailable. Both coordinates are required; no address lookup is needed.</p>
                <label>Latitude<input required type="number" step="any" min="-90" max="90" disabled={confirmed or locating or saving} value={latitude} onChange={lambda (e: ChangeEvent) { latitude = e.target.value; }}/></label>
                <label>Longitude<input required type="number" step="any" min="-180" max="180" disabled={confirmed or locating or saving} value={longitude} onChange={lambda (e: ChangeEvent) { longitude = e.target.value; }}/></label>
                {confirmed and <p>Confirmed location: {latitude}, {longitude}</p>}
                {confirmed and <LocationLink latitude={Number(latitude)} longitude={Number(longitude)}/>}
                <button type="button" onClick={changeLocation if confirmed else confirmLocation} disabled={locating or saving}>{"Change location" if confirmed else "Confirm location"}</button>
                <label>Location description (optional)<input maxLength={500} disabled={saving} value={locationText} onChange={lambda (e: ChangeEvent) { locationText = e.target.value; }}/></label>
                <button type="submit" disabled={saving or locating or not confirmed or loading}>{"Saving report…" if saving else "Submit report"}</button>
            </form>
            <p role="status" aria-live="polite" className="form-message">{feedback}</p>
            {not loading and len(categories) == 0 and <button className="quiet" onClick={loadReports}>Retry loading categories</button>}
        </section>
    </div>
}
