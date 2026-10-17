impl app.load(display_name: str = "") -> None {
    current: AccountView | None = None;
    listed: list[OrganizationView] = [];
    current = await account(display_name=display_name);
    me = current;
    if current.organization is not None {
        orgName = current.organization.name;
        description = current.organization.description;
    }
    if "audit:read" in current.capabilities {
        listed = await organizations();
    }
    items = listed;
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
