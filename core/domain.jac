"""Task 1 domain. Identity is always the current authenticated Jac root."""
import os;
import from jaclang { JacRuntime as Jac }
import from datetime { datetime, timezone }

node EcoUser {
    has display_name: str = "Citizen",
        account_status: str = "active",
        volunteer_enabled: bool = False,
        created_at: str = "",
        updated_at: str = "",
        revision: int = 1;
}

node Organization {
    has name: str,
        description: str,
        created_by: str,
        verification_status: str = "pending",
        created_at: str = "",
        updated_at: str = "",
        verified_at: str = "",
        verified_by: str = "",
        reviewed_at: str = "",
        reviewed_by: str = "",
        revision: int = 1;

    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.WRITE; }
        if self.created_by == jid(root) { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}

edge OrganizationIndex: any --> Organization {
    def __jac_access__ -> AccessLevel { return AccessLevel.READ; }
}

node OrganizationMembership {
    has user_id: str,
        organization_id: str,
        role: str = "organization_admin",
        status: str = "active",
        created_at: str = "",
        revision: int = 1;
}

node OrganizationReview {
    has organization_id: str,
        reviewer: str,
        timestamp: str,
        previous_status: str,
        resulting_status: str,
        revision: int;

    def __jac_access__ -> AccessLevel {
        if is_authority() { return AccessLevel.READ; }
        return AccessLevel.NO_ACCESS;
    }
}

obj OrganizationView {
    has id: str,
        name: str,
        description: str,
        verification_status: str,
        created_by: str,
        created_at: str,
        updated_at: str,
        verified_at: str,
        verified_by: str,
        reviewed_at: str,
        reviewed_by: str,
        revision: int;
}

obj AccountView {
    has display_name: str,
        account_status: str,
        volunteer_enabled: bool,
        created_at: str,
        updated_at: str,
        revision: int,
        root_id: str,
        capabilities: list[str],
        organization: OrganizationView | None;
}

def now() -> str { return datetime.now(timezone.utc).isoformat(); }

# Configure immutable Jac root IDs, never a username/role submitted by a client.
# This also avoids someone registering an as-yet-unclaimed allowlisted username.
def require_authenticated() -> None {
    if jid(root) == jid(root.shared) or jid(root) == str(Jac.get_context().system_root.id) {
        raise PermissionError("An authenticated user root is required.");
    }
}

def is_authority() -> bool {
    if jid(root) == jid(root.shared) or jid(root) == str(Jac.get_context().system_root.id) {
        return False;
    }
    configured = os.environ.get("ECOTRACK_AUTHORITY_ROOT_IDS", "");
    return jid(root) in [value.strip() for value in configured.split(",") if value.strip()];
}

def ensure_profile(display_name: str = "") -> EcoUser {
    require_authenticated();
    profiles = [root --> [?:EcoUser]];
    if profiles { return profiles[0]; }
    # Touch the existing root as a native optimistic-concurrency guard.
    Jac.get_context().mem.mark_dirty(root.__jac__);
    stamp = now();
    return root ++> EcoUser(display_name=display_name.strip()[:100] or "Citizen",
                           created_at=stamp, updated_at=stamp);
}

def own_organization() -> Organization | None {
    for member in [root --> [?:OrganizationMembership]] {
        if member.user_id == jid(root) and member.status == "active" {
            for org in [member --> [?:Organization]] {
                if jid(org) == member.organization_id { return org; }
            }
        }
    }
    return None;
}

def capabilities() -> list[str] {
    profile = ensure_profile();
    if profile.account_status != "active" { return []; }
    result = ["organization:apply", "organization:read_own", "organization:edit_pending"];
    if is_authority() {
        result += ["organization:verify", "organization:suspend", "audit:read"];
    }
    org = own_organization();
    if org is not None and org.verification_status == "verified" {
        result += ["organization:verified_member"];
    }
    return result;
}

def require_capability(capability: str) -> None {
    if capability not in capabilities() { raise PermissionError("Forbidden: " + capability); }
}

def org_view(org: Organization) -> OrganizationView {
    return OrganizationView(id=jid(org), name=org.name, description=org.description,
        verification_status=org.verification_status, created_by=org.created_by,
        created_at=org.created_at, updated_at=org.updated_at,
        verified_at=org.verified_at, verified_by=org.verified_by,
        reviewed_at=org.reviewed_at, reviewed_by=org.reviewed_by, revision=org.revision);
}

def validate_details(name: str, description: str) -> None {
    if not name.strip() or len(name.strip()) > 160 {
        raise ValueError("Organization name must contain 1–160 characters.");
    }
    if not description.strip() or len(description.strip()) > 3000 {
        raise ValueError("Description must contain 1–3000 characters.");
    }
}

def check_revision(org: Organization, expected_revision: int) -> None {
    if org.revision != expected_revision {
        raise ValueError("Application changed. Refresh before trying again.");
    }
}

def apply_organization(name: str, description: str) -> OrganizationView {
    require_capability("organization:apply");
    if own_organization() is not None {
        raise ValueError("One organization application per account is allowed.");
    }
    validate_details(name, description);
    # Serialize two simultaneous applications against the same persisted profile.
    profile = ensure_profile();
    profile.revision += 1;
    profile.updated_at = now();
    stamp = now();
    org = Organization(name=name.strip(), description=description.strip(),
        created_by=jid(root), created_at=stamp, updated_at=stamp);
    member = root ++> OrganizationMembership(user_id=jid(root),
        organization_id=jid(org), created_at=stamp);
    member ++> org;
    root.shared +>:OrganizationIndex:+> org;
    return org_view(org);
}

def edit_application(organization_id: str, name: str, description: str,
                     expected_revision: int) -> OrganizationView {
    require_capability("organization:edit_pending");
    org = own_organization();
    if org is None or jid(org) != organization_id {
        raise PermissionError("Only your own application may be edited.");
    }
    check_revision(org, expected_revision);
    if org.verification_status != "pending" { raise ValueError("Only pending applications may be edited."); }
    validate_details(name, description);
    org.name = name.strip();
    org.description = description.strip();
    org.updated_at = now();
    org.revision += 1;
    return org_view(org);
}

def review_application(organization_id: str, decision: str, expected_revision: int) -> OrganizationView {
    require_capability("organization:suspend" if decision == "suspended" else "organization:verify");
    # Resolve exclusively from the authority index, after the capability check.
    for org in [root.shared ->:OrganizationIndex:->][?:Organization] {
        if jid(org) != organization_id { continue; }
        if org.created_by == jid(root) { raise PermissionError("You cannot review your own organization."); }
        check_revision(org, expected_revision);
        previous = org.verification_status;
        if not ((previous == "pending" and decision in ["verified", "rejected"])
                or (previous == "verified" and decision == "suspended")) {
            raise ValueError("Invalid verification transition.");
        }
        stamp = now();
        org.verification_status = decision;
        org.reviewed_by = jid(root);
        org.reviewed_at = stamp;
        org.updated_at = stamp;
        org.revision += 1;
        if decision == "verified" {
            org.verified_at = stamp;
            org.verified_by = jid(root);
        }
        org ++> OrganizationReview(organization_id=jid(org), reviewer=jid(root),
            timestamp=stamp, previous_status=previous, resulting_status=decision,
            revision=org.revision);
        return org_view(org);
    }
    raise ValueError("Organization not found.");
}
