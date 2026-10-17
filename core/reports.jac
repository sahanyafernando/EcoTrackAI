"""Citizen observations, stored independently of any future Incident entity."""
import from math { isfinite }
import from jaclang { JacRuntime as Jac }
import from core.domain { now, is_authority, require_capability, ensure_profile }

glob REPORT_CATEGORIES: tuple[str, ...] = (
    "illegal_dumping", "overflowing_waste", "water_pollution",
    "blocked_drain", "damaged_public_space", "other"
);

node Report {
    has reporter_id: str,
        description: str,
        category: str,
        latitude: float,
        longitude: float,
        location_text: str = "",
        evidence_ref: str = "",
        submitted_at: str = "",
        status: str = "submitted",
        created_at: str = "",
        updated_at: str = "",
        revision: int = 1,
        submission_id: str = "";

    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}

# The index is traversable only by reviewers. Report ownership remains with the citizen.
edge IncomingReport: any --> Report {
    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}

obj ReportView {
    has id: str,
        description: str,
        category: str,
        latitude: float,
        longitude: float,
        location_text: str,
        evidence_ref: str,
        submitted_at: str,
        status: str,
        created_at: str,
        updated_at: str,
        revision: int;
}

def report_view(item: Report) -> ReportView {
    # Do not serialize reporter identity, credentials, or internal request IDs.
    return ReportView(id=jid(item), description=item.description, category=item.category,
        latitude=item.latitude, longitude=item.longitude, location_text=item.location_text,
        evidence_ref=item.evidence_ref, submitted_at=item.submitted_at, status=item.status,
        created_at=item.created_at, updated_at=item.updated_at, revision=item.revision);
}

def validate_report(description: str, category: str, latitude: float, longitude: float,
                    location_text: str, submission_id: str) -> None {
    if not description.strip() or len(description.strip()) > 5000 {
        raise ValueError("Description must contain 1–5000 characters.");
    }
    if category not in REPORT_CATEGORIES { raise ValueError("Choose a valid report category."); }
    if not isfinite(latitude) or not -90 <= latitude <= 90 {
        raise ValueError("Latitude must be a finite number from -90 to 90.");
    }
    if not isfinite(longitude) or not -180 <= longitude <= 180 {
        raise ValueError("Longitude must be a finite number from -180 to 180.");
    }
    if len(location_text.strip()) > 500 { raise ValueError("Location description must be at most 500 characters."); }
    if not 16 <= len(submission_id) <= 100 {
        raise ValueError("A submission ID of 16–100 characters is required for safe retries.");
    }
}

def submit_report(description: str, category: str, latitude: float, longitude: float,
                  location_text: str, submission_id: str) -> ReportView {
    require_capability("report:create");
    validate_report(description, category, latitude, longitude, location_text, submission_id);
    # This key suppresses transport retries only, never clusters real-world observations.
    for item in [root --> [?:Report]] {
        if item.reporter_id == jid(root) and item.submission_id == submission_id {
            if (item.description != description.strip() or item.category != category
                or item.latitude != latitude or item.longitude != longitude
                or item.location_text != location_text.strip()) {
                raise ValueError("This submission was already saved with different details. Refresh My Reports.");
            }
            return report_view(item);
        }
    }
    # Use an existing native graph anchor to guard concurrent replay of the same draft.
    profile = ensure_profile();
    profile.revision += 1;
    profile.updated_at = now();
    Jac.get_context().mem.mark_dirty(root.__jac__);
    stamp = now();
    item = root ++> Report(reporter_id=jid(root), description=description.strip(),
        category=category, latitude=latitude, longitude=longitude,
        location_text=location_text.strip(), submitted_at=stamp, created_at=stamp,
        updated_at=stamp, submission_id=submission_id);
    root.shared +>:IncomingReport:+> item;
    return report_view(item);
}

def own_reports() -> list[ReportView] {
    require_capability("report:read_own");
    return [report_view(item) for item in [root --> [?:Report, -submitted_at]]
            if item.reporter_id == jid(root)];
}

def incoming_reports() -> list[ReportView] {
    require_capability("report:read_all");
    return [report_view(item) for item in [root.shared ->:IncomingReport:-> [?:Report, -submitted_at]]];
}

def inspect_report(report_id: str) -> ReportView {
    require_capability("report:read_own");
    # IDs select within an authorized collection; an ID never grants graph access.
    for item in own_reports() {
        if item.id == report_id { return item; }
    }
    if is_authority() {
        for item in incoming_reports() {
            if item.id == report_id { return item; }
        }
    }
    raise PermissionError("Report unavailable or access denied.");
}
