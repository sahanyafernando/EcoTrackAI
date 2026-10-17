"""Lead-owned official events and identity-bound participation; no AI scheduling."""
import from datetime { datetime, timezone }
import from math { isfinite }
import from uuid { uuid5, NAMESPACE_URL }
import from jaclang { JacRuntime as Jac }
import from core.domain { require_capability, capabilities, require_authenticated, own_organization, ensure_profile, now }
import from core.incidents { Incident, IncidentIndex }
import from core.responses { check_existing_lead }
import from agents.incident_intelligence { analysis_lock }
import from contracts.cleanup_views { CapacityState, CleanupEventView, CleanupLeadOption, CleanupBoardView }

def can_read_cleanups() -> bool {
    try { require_capability("cleanup:read"); return True; }
    except PermissionError { return False; }
}
def manages_incident(incident_id: str, organization_id: str = "") -> bool {
    if "cleanup:manage" not in capabilities() { return False; }
    org = own_organization();
    if org is None or org.verification_status != "verified" { return False; }
    if organization_id and jid(org) != organization_id { return False; }
    lead = check_existing_lead(incident_id);
    return lead is not None and lead.organization_id == jid(org);
}
node CleanupEvent {
    has incident_id: str, lead_organization_id: str, organization_name: str, category: str,
        title: str, description: str, location_text: str, latitude: float, longitude: float,
        scheduled_at: str, required_volunteers: int, created_at: str, updated_at: str,
        status: str = "planned", revision: int = 1;
    def __jac_access__ -> AccessLevel {
        if not can_read_cleanups() { return AccessLevel.NO_ACCESS; }
        if manages_incident(self.incident_id, self.lead_organization_id) { return AccessLevel.WRITE; }
        return AccessLevel.READ;
    }
}
node VolunteerParticipation {
    has event_id: str, user_id: str, status: str, joined_at: str, updated_at: str;
    def __jac_access__ -> AccessLevel {
        if self.user_id == jid(root) { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
# Public counting projection avoids exposing private user/root IDs to other citizens.
# Each citizen owns one canonical projection per event, updated with their private
# participation in the same transaction. No cached event-wide counter is trusted.
node VolunteerAttendance {
    has event_id: str, status: str;
    def __jac_access__ -> AccessLevel {
        if can_read_cleanups() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
edge CleanupIndex: any --> any {
    def __jac_access__ -> AccessLevel {
        if can_read_cleanups() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}
def find_event(event_id: str) -> CleanupEvent {
    require_capability("cleanup:read");
    for item in [root.shared ->:CleanupIndex:-> [?:CleanupEvent]] {
        if jid(item) == event_id { return item; }
    }
    raise ValueError("Cleanup event not found.");
}
def own_participation(event_id: str) -> VolunteerParticipation | None {
    require_authenticated();
    for item in [root --> [?:VolunteerParticipation]] {
        if item.event_id == event_id and item.user_id == jid(root) { return item; }
    }
    return None;
}
def count_joined_volunteers(event_id: str) -> int {
    find_event(event_id);
    return len([item for item in [root.shared ->:CleanupIndex:-> [?:VolunteerAttendance]]
        if item.event_id == event_id and item.status == "joined"]);
}
def get_event_capacity_state(event_id: str) -> CapacityState {
    event = find_event(event_id);
    joined = count_joined_volunteers(event_id);
    return CapacityState(event_id=event_id, required=event.required_volunteers,
        joined=joined, remaining=max(0, event.required_volunteers - joined));
}
def remaining_volunteers_needed(event_id: str) -> int {
    return get_event_capacity_state(event_id).remaining;
}
def event_view(item: CleanupEvent) -> CleanupEventView {
    capacity = get_event_capacity_state(jid(item));
    mine = own_participation(jid(item));
    return CleanupEventView(event_id=jid(item), incident_id=item.incident_id,
        lead_organization_id=item.lead_organization_id, organization_name=item.organization_name,
        category=item.category, title=item.title, description=item.description,
        location_text=item.location_text, latitude=item.latitude, longitude=item.longitude,
        scheduled_at=item.scheduled_at, required_volunteers=item.required_volunteers,
        status=item.status, created_at=item.created_at, updated_at=item.updated_at, revision=item.revision,
        joined_volunteers=capacity.joined, remaining_needed=capacity.remaining,
        my_participation=mine.status if mine is not None else "none",
        can_manage=manages_incident(item.incident_id, item.lead_organization_id));
}
def cleanup_board() -> CleanupBoardView {
    require_capability("cleanup:read");
    events = [event_view(item) for item in [root.shared ->:CleanupIndex:-> [?:CleanupEvent, -created_at]]];
    options: list[CleanupLeadOption] = [];
    if "cleanup:manage" in capabilities() {
        for incident in [root.shared ->:IncidentIndex:-> [?:Incident]] {
            if incident.status == "confirmed" and manages_incident(jid(incident))
                and not any([event.incident_id == jid(incident) for event in events]) {
                options.append(CleanupLeadOption(incident_id=jid(incident), category=incident.category));
            }
        }
    }
    return CleanupBoardView(events=events, lead_incidents=options);
}
def create_cleanup(incident_id: str, title: str, description: str, location_text: str,
    latitude: float, longitude: float, scheduled_at: str, required_volunteers: int) -> CleanupEventView {
    require_capability("cleanup:manage");
    if not manages_incident(incident_id) { raise PermissionError("Only the active verified Lead organization can create an official event."); }
    if not title.strip() or len(title.strip()) > 160 or not description.strip() or len(description.strip()) > 3000
        or not location_text.strip() or len(location_text.strip()) > 500 {
        raise ValueError("Provide a title (1–160), description (1–3000) and location (1–500 characters).");
    }
    if not isfinite(latitude) or not isfinite(longitude) or not -90 <= latitude <= 90 or not -180 <= longitude <= 180 {
        raise ValueError("Valid finite latitude and longitude are required.");
    }
    if type(required_volunteers) is not int or not 1 <= required_volunteers <= 1000 {
        raise ValueError("Required volunteers must be an integer from 1 to 1000.");
    }
    try { scheduled = datetime.fromisoformat(scheduled_at); }
    except ValueError { raise ValueError("Provide a valid scheduled date/time with timezone."); }
    if scheduled.tzinfo is None or scheduled <= datetime.now(timezone.utc) {
        raise ValueError("Schedule a future date/time with a timezone.");
    }
    if not analysis_lock.acquire(blocking=False) { raise ValueError("An operation is running. Retry shortly."); }
    try {
        Jac.commit(); Jac.get_context().mem.read_barrier();
        if not manages_incident(incident_id) { raise PermissionError("Current verified Lead membership is required."); }
        for item in [root.shared ->:CleanupIndex:-> [?:CleanupEvent]] {
            if item.incident_id == incident_id { raise ValueError("An official cleanup event already exists for this Incident."); }
        }
        org = own_organization();
        if org is None { raise PermissionError("Organization membership required."); }
        lead = check_existing_lead(incident_id);
        if lead is None { raise PermissionError("Active Lead required."); }
        category = "";
        for incident in [root.shared ->:IncidentIndex:-> [?:Incident]] {
            if jid(incident) == incident_id { category = incident.category; }
        }
        profile = ensure_profile(); profile.revision += 1; profile.updated_at = now();
        stamp = now();
        event = CleanupEvent(incident_id=incident_id, lead_organization_id=jid(org),
            organization_name=lead.organization_name, category=category,
            title=title.strip(), description=description.strip(), location_text=location_text.strip(),
            latitude=latitude, longitude=longitude, scheduled_at=scheduled.astimezone(timezone.utc).isoformat(),
            required_volunteers=required_volunteers, created_at=stamp, updated_at=stamp);
        event.__jac__.id = uuid5(NAMESPACE_URL, "ecotrack:cleanup:" + incident_id);
        root ++> event; root.shared +>:CleanupIndex:+> event;
        Jac.commit();
        return event_view(event);
    } finally { analysis_lock.release(); }
}
def change_cleanup_status(event_id: str, status: str, expected_revision: int) -> CleanupEventView {
    require_capability("cleanup:manage");
    if not analysis_lock.acquire(blocking=False) { raise ValueError("An operation is running. Retry shortly."); }
    try {
        Jac.commit(); Jac.get_context().mem.read_barrier();
        event = find_event(event_id);
        if not manages_incident(event.incident_id, event.lead_organization_id) { raise PermissionError("Only this event's current verified Lead can manage it."); }
        if event.revision != expected_revision { raise ValueError("Event changed. Refresh before managing it."); }
        if not ((event.status == "planned" and status in ["active", "cancelled"])
            or (event.status == "active" and status in ["completed", "cancelled"])) {
            raise ValueError("Invalid cleanup status transition.");
        }
        event.status = status; event.updated_at = now(); event.revision += 1;
        Jac.commit();
        return event_view(event);
    } finally { analysis_lock.release(); }
}
def participate(event_id: str, joining: bool) -> CleanupEventView {
    require_capability("cleanup:join");
    if not analysis_lock.acquire(blocking=False) { raise ValueError("An operation is running. Retry shortly."); }
    try {
        Jac.commit(); Jac.get_context().mem.read_barrier();
        event = find_event(event_id);
        if joining and event.status not in ["planned", "active"] { raise ValueError("This event is not accepting volunteers."); }
        mine = own_participation(event_id);
        status = "joined" if joining else "withdrawn";
        if (mine is not None and mine.status == status) or (mine is None and not joining) {
            raise ValueError("You already joined this event." if joining else "You have no joined participation to withdraw.");
        }
        profile = ensure_profile(); profile.revision += 1; profile.updated_at = now();
        stamp = now();
        if mine is None {
            mine = VolunteerParticipation(event_id=event_id, user_id=jid(root), status=status, joined_at=stamp, updated_at=stamp);
            mine.__jac__.id = uuid5(NAMESPACE_URL, "ecotrack:volunteer:" + event_id + ":" + jid(root));
            root ++> mine;
            attendance = VolunteerAttendance(event_id=event_id, status=status);
            attendance.__jac__.id = uuid5(NAMESPACE_URL, "ecotrack:attendance:" + event_id + ":" + jid(root));
            root ++> attendance; root.shared +>:CleanupIndex:+> attendance;
        } else {
            mine.status = status; mine.updated_at = stamp;
            if joining { mine.joined_at = stamp; }
            for attendance in [root --> [?:VolunteerAttendance]] {
                if attendance.event_id == event_id { attendance.status = status; }
            }
        }
        Jac.commit();
        return event_view(event);
    } finally { analysis_lock.release(); }
}
