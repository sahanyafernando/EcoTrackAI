impl app.load(display_name: str = "") -> None {
    current: AccountView | None = None;
    listed: list[OrganizationView] = [];
    mine: list[ReportView] = [];
    incoming: list[ReportView] = [];
    dataLoading = True;
    try {
        current = await account(display_name=display_name);
        me = current;
        page = resolve_page(workspace_context(current.capabilities, current.organization is not None), page);
        if current.organization is not None {
            orgName = current.organization.name;
            description = current.organization.description;
        }
        organizationError = "";
        ownReportsError = "";
        incomingError = "";
        if "audit:read" in current.capabilities {
            try { listed = await organizations(); }
            except Exception { organizationError = "Organizations could not be loaded. Use Refresh to retry."; }
        }
        if "report:read_own" in current.capabilities {
            try { mine = await my_reports(); }
            except Exception { ownReportsError = "Your reports could not be loaded. Use Refresh to retry."; }
        }
        if "report:read_all" in current.capabilities {
            try { incoming = await all_reports(); }
            except Exception { incomingError = "Incoming reports could not be loaded. Use Refresh to retry."; }
        }
        items = listed;
        ownReports = mine;
        incomingReports = incoming;
    } finally { dataLoading = False; }
}

impl app.recover -> None {
    try {
        if jacIsLoggedIn() { await load(); }
    } except Exception {
        jacLogout();
        me = None;
        message = "Your session could not be recovered. Please login again.";
    } finally { recovering = False; }
}

impl app.authenticate(e: FormEvent) -> None {
    e.preventDefault();
    busy = True;
    message = "";
    signup: SignupResult | None = None;
    ok: bool = False;
    try {
        if registering {
            signup = await jacSignup([{"type": "username", "value": username.strip()}], password);
            if not signup.success {
                message = signup.error or "Registration failed.";
                return;
            }
        }
        ok = await jacLogin({"type": "username", "value": username.strip()}, password);
        if not ok { message = "Login failed. Check your username and password."; return; }
        password = "";
        await load(displayName if registering else "");
    } except Exception {
        message = "Unable to sign in. Please try again.";
    } finally { busy = False; }
}

impl app.logout -> None {
    jacLogout();
    me = None;
    items = [];
    ownReports = [];
    incomingReports = [];
    page = "overview";
    password = "";
    displayName = "";
    orgName = "";
    description = "";
    message = "You have logged out.";
}

impl app.saveOrganization(e: FormEvent) -> None {
    e.preventDefault();
    if me is None { return; }
    busy = True;
    message = "";
    try {
        if me.organization is None {
            await apply(name=orgName, description=description);
        } else {
            await edit_organization(organization_id=me.organization.id,
                name=orgName, description=description, expected_revision=me.organization.revision);
        }
        await load();
        message = "Application saved.";
    } except Exception as error {
        message = "Could not save application: " + str(error);
    } finally { busy = False; }
}

impl app.decide(org: OrganizationView, decision: str) -> None {
    busy = True;
    message = "";
    try {
        await review(organization_id=org.id, decision=decision, expected_revision=org.revision);
        await load();
        message = "Organization status updated to " + decision + ".";
    } except Exception as error {
        message = "Review failed: " + str(error) + " Refresh before trying again.";
    } finally { busy = False; }
}

impl app.refresh -> None {
    busy = True;
    try { await load(); message = "Updated."; }
    except Exception { message = "Unable to refresh. Please try again."; }
    finally { busy = False; }
}


impl app.navigate(destination: str) -> None {
    if me is None { return; }
    page = resolve_page(workspace_context(me.capabilities, me.organization is not None), destination);
    message = "";
    globalThis.window.scrollTo({"top": 0, "behavior": "instant"});
    globalThis.document.getElementById("page-content").focus();
}

impl app.reportSaved(item: ReportView) -> None {
    ownReports = [item] + [previous for previous in ownReports if previous.id != item.id];
    ownReportsError = "";
    if me is not None and "report:read_all" in me.capabilities {
        incomingReports = [item] + [previous for previous in incomingReports if previous.id != item.id];
        incomingError = "";
    }
}
