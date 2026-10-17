# EcoTrack AI

Jac-powered environmental coordination. **Implemented: authentication, RBAC, organization verification,
citizen environmental reports with GPS/manual coordinates, and a role-aware
application shell (Tasks 1–2.5).**

Requires **Jac 0.37.23**. From this directory:

```bash
jac install
jac run
```

Open the App URL printed by Jac (normally `http://localhost:8000`). Register and
login with a **username**, not an assumed email address. Jac owns passwords,
JWTs, session storage, and the persistent graph; EcoTrack stores no credentials.
Reload recovers the Jac session and loads the application profile. Logout clears
the runtime session on this browser; Jac 0.37.23 does not revoke issued JWTs.

## Initial Central Authority

1. Start the app without an authority allowlist. Register the intended authority
   account, login, and open **Profile → Advanced account details** to copy its
   **Account root**.
2. Stop the server. Configure that exact root ID in the **server environment**:

   ```bash
   export ECOTRACK_AUTHORITY_ROOT_IDS='paste-the-account-root-id-here'
   jac run
   ```

3. Login as that same account (or refresh its recovered session). The Authority
   dashboard can inspect applications and verify/reject/suspend organizations.

For multiple reviewers, comma-separate their root IDs. An empty/unset value grants
nobody authority. IDs must come from accounts you control. Removing an ID removes
EcoTrack authority on subsequent requests. Configuration stays on the server;
client-supplied roles or IDs never promote an account. Root IDs are used instead
of usernames to avoid granting authority to someone who registers an unclaimed
allowlisted username. No password is hard-coded. The separate Jac admin portal
and its default-account bootstrap are disabled in `jac.toml`.

For deployment, configure Jac's signing secret with `JAC_SERVE_AUTH_SECRET` and
serve over HTTPS. Do not commit `.env` or runtime data. `.env.example` describes
the configuration; exporting variables in your shell works without a dotenv loader.

## Implemented behavior

- Citizen: idempotent application profile; one organization application per
  account, including after rejection/suspension; edit own pending application.
- Applicant/admin: initial active `organization_admin` membership; view own status.
- Verified member: verified capability exists only while the organization status
  is exactly `verified`. No response operations are implemented in Task 1.
- Central Authority: list/inspect applications, `pending → verified/rejected`,
  `verified → suspended`. Reviewers cannot review their own organization.
- Every review records reviewer root, timestamp, status, revision, and a persistent
  review record. Pending edits and reviews require the current revision.

All application endpoints use Jac `:protect`; shared core capability checks enforce
policy. Unrelated accounts cannot list/read or edit other organizations.

## Validation

```bash
jac check
jac check --nowarn
JAC_TEST_JOBS=0 jac test
git diff --check
jac run
```

See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for test coverage,
validation results, and remaining manual checks. Incident processing, agents,
cleanups, volunteering, notifications, analytics, mobile, and CLI are deferred.

## Citizen reports and location (Task 2)

Open **Report Issue** to describe one environmental observation, choose a
category, and supply coordinates. **Use my current location** asks the browser
for location permission only when clicked. GPS needs HTTPS or localhost. Denial,
unavailability, and timeout show retry instructions; manually entered coordinates
work without GPS or a geocoding API. Latitude must be -90…90 and longitude
-180…180. Review and **Confirm location** before submitting; use **Change location**
to replace a confirmed position.

The core owns the fixed categories: `illegal_dumping`, `overflowing_waste`,
`water_pollution`, `blocked_drain`, `damaged_public_space`, `other`. The form loads
them from the server. Description is required (1–5000 trimmed characters); location
text is optional (up to 500). Both finite coordinates are required, including when
GPS fails. A location description alone is insufficient in this milestone.

A persisted Report holds a stable Jac ID, reporter root reference, description,
category, coordinates, optional location text, reserved evidence reference,
submitted/created/updated timestamps, `submitted` status, and revision 1. Reports
are immutable through the API in Task 2. A draft request ID prevents duplicate saves
when the same submission is retried; separate observations remain separate reports.

**My Reports** lists your saved observations after refresh/logout/login. Citizen
accounts, including organization applicants/members, retain access to their own
reports. Only configured Central Authority receives `report:read_all` and the
**Incoming Reports** view. An organization’s verification never grants access to
other citizens’ raw reports. Client views omit reporter identity and private profile
data. Reporting endpoints are authenticated and enforce capabilities in core.

**View position on OpenStreetMap** opens a marker at the report coordinates in a
new tab. There is no embedded tracker, map library, API key, reverse geocoder, or
routing. Coordinates are sent to OpenStreetMap only when the link is opened.
Image upload is deferred: Jac supports multipart upload, but private storage,
content validation, and authenticated image serving need a separate implementation.
`evidence_ref` is reserved and empty; arbitrary evidence URLs are not accepted.

Task 3 will address related-report/duplicate intelligence and incident review.
No incident, cluster, LLM call, agent, or organization response flow is created here.

## Application pages (Task 2.5)

One shared shell selects navigation from the authenticated server account. Central
Authority takes precedence over organization membership; an organization application
in any verification state selects the Organization workspace. Other accounts use
the Citizen workspace. Navigation does not grant permissions; core RBAC is unchanged.

- **Citizen:** Overview with real report counts/recent reports, Report Issue,
  My Reports, Cleanup Events (planned), Profile.
- **Organization:** Overview with actual application status, Organization details
  and pending edits, Incidents (planned), Cleanup Events (planned), Volunteers (planned).
- **Central Authority:** Authority Overview with real counts, Incoming Reports,
  Organization Review, Incident Review (planned), Agent Activity (planned), Audit.
  Audit shows only each organization's latest available decision metadata; full
  audit history is marked as not implemented yet.

Profile is accessible through the sidebar account control in every workspace.
It includes the organization application entry point and personal reporting tools,
so organization/authority users can still submit and view their own citizen reports.
Planned pages say **Not implemented yet** and contain no sample data or fake metrics.

Desktop uses a fixed sidebar; mobile uses a navigation drawer. View state is managed
in Jac without a new router/framework; reload recovers the session at Overview.
The report form stays mounted while switching views to preserve the current draft
and GPS confirmation; logout clears the authenticated view. Dates display in your
browser's locale/timezone. Use Refresh to reload server account/data changes.
