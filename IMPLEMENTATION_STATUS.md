# Implementation status — Tasks 1, 2 and 2.5

Task 1: Auth + RBAC + organization verification. Application and tests are Jac;
there is no second backend, credential system, or frontend stack.

## Files and design

- `core/domain.jac`: persisted EcoUser, Organization, OrganizationMembership,
  OrganizationReview; typed client views; capability checks and domain operations.
- `endpoints.jac`: protected account, apply, edit_organization, organizations, review RPCs.
- `frontend.jac`, `frontend.impl.jac`, `main.jac`: native Jac auth and minimal web UI.
- `jac.toml`: pinned runtime retained; separate runtime admin bootstrap disabled.
- `tests/organizations.jac`, `tests/organizations.test.jac`: isolated native Jac
  endpoint tests using real JWT identities, graph ACLs, and persistence.
- `.env.example`, `README.md`: configuration and bootstrap instructions.

EcoUser belongs to the authenticated root and stores display_name, account_status,
volunteer_enabled=false, timestamps, and revision. Reinitialization preserves the
existing profile. No passwords or tokens are copied into application nodes.

An application creates one active organization_admin membership under the caller's
root, linking to its Organization. The shared graph holds an authority index;
organization ACLs deny unrelated readers and permit configured reviewers.
Authorization always runs before looking up a review target. No arbitrary node-ID
lookup substitutes for ownership. Views contain organization/application details,
not another citizen's profile or credentials.

Capabilities are centralized: organization:apply, organization:read_own,
organization:edit_pending, organization:verify, organization:suspend, audit:read,
and a verification-dependent organization:verified_member marker. Future response
powers are deliberately absent. Non-active profiles receive no capabilities.

Each review stores reviewer, timestamp, previous/resulting status, and revision in
an appended OrganizationReview node. Latest review metadata is also on Organization;
verified_at/by retain the original verification when suspended. Blank strings mean
an unset timestamp/reviewer. The deferred `revoked` state from the broader planning
model is outside this explicitly four-state milestone.

The one-application rule also applies to rejected/suspended accounts. Pending
applications alone can be edited. Reviews reject stale revisions and invalid
transitions. Jac 0.37.23 concurrency testing found that an empty-neighbor lookup
alone could create duplicates: profile initialization explicitly marks the existing
root dirty through Jac's persistence API, and application creation updates the
existing profile revision, so native optimistic concurrency protects uniqueness.
A losing concurrent request may receive a runtime transaction error; refresh/retry
is safe. Cross-worker/load behavior beyond the local server is not certified.

## Task 1 validation (historical)

`JAC_TEST_JOBS=0 jac test`: eight tests, including:

- A three-account lifecycle: authenticated profile initialization/idempotence;
  pending application and initial membership; duplicate rejection; pending edits;
  stale edit/review rejection; citizen/applicant review and listing denial;
  cross-user edit denial; authority verification/rejection/suspension;
  authority self-review denial; reviewer/timestamp/revision metadata;
  suspended capability removal; config-based authority revocation; login recovery.
- Five parameterized tests: anonymous access denied for every protected RPC.
- Concurrent requests: one initialized profile and one accepted application.
- Direct core operations deny an explicitly bound anonymous root.

Final validation on Jac 0.37.23:

- `jac check`: exit 0 (compiler warnings remain, chiefly JSX-name and generated setter warnings).
- `jac check --nowarn`: exit 0.
- `jac check tests --nowarn`: exit 0.
- `JAC_TEST_JOBS=0 jac test`: exit 0, 8 passed.
- `git diff --check`: exit 0.
- `jac run`: server ready; App localhost:8000 and API localhost:8001.

Temporary browser validation accounts, their applications, and the default admin
created during the initial runtime inspection were removed. No demo data is seeded.

Browser validation uses actual registered accounts and applications, not UI fixtures:
registration, login, citizen dashboard, pending application, reload/session recovery,
logout; authority pending list, verify, reject, suspend; applicant suspended status;
role-specific UI; no JavaScript exceptions; no horizontal overflow at 390px.

## Manual follow-up and deferred work

Use your own accounts to confirm the bootstrap instructions and chosen display names,
and review the UI on your preferred browser/device. Production HTTPS, deployment
secret configuration, multi-worker concurrency/load, and deployment persistence are
not validated here. Jac logout clears the browser session but issued tokens remain
valid until expiry in this runtime.

Task 1 originally deferred reporting and GPS; these are now implemented below.
Still deferred: incidents, deduplication, AI agents, cleanups, volunteer functionality,
notifications, analytics, mobile application, CLI,
organization invitations/multiple memberships, resubmission, reactivation, or revoked
status. The unused generated MessageCard component remains, but the guestbook backend
and visible experience have been replaced. Local planning docs remain ignored.


## Task 2 — Citizen reports + GPS + basic map

Created `core/reports.jac`, `components/ReportPanel.jac` and its implementation
annex, `components/ReportCard.jac`, `tests/reports.jac` and its test annex. Extended
`core/domain.jac` capabilities, `endpoints.jac`, and the existing authenticated shell
in `frontend.jac`. No dependency/configuration or authority bootstrap change.
Application logic and tests remain Jac; no JavaScript/TypeScript subsystem was added.

Report is a citizen observation, separate from any future Incident. It persists
under the caller’s root and has reporter_id, description, canonical category,
latitude/longitude, optional location_text, empty evidence_ref, submitted_at,
created_at/updated_at, `submitted` status, revision=1, and an internal submission_id.
The stable public ID is `jid(report)`. A protected shared IncomingReport edge
indexes reports for authority review. Report and index ACLs deny unrelated users;
authorities have read access. Report views omit reporter_id and submission_id.

New capabilities: report:create and report:read_own for active accounts;
report:read_all only for existing server-configured Central Authority. Organization
verification gives no access to other users’ reports. The protected RPCs are
report_categories, create_report, my_reports, get_report, all_reports. Core checks
precede reads/writes and IDs only select inside authorized collections. There is
no edit/status-transition endpoint: every saved observation starts as submitted
and cannot be promoted to an incident status by a caller.

Core validation: trimmed description 1–5000 chars, six canonical categories,
finite latitude -90…90, finite longitude -180…180, optional trimmed location text
up to 500 chars, submission ID 16–100 chars. One request key is retained per draft
for safe replay; mismatched payloads with an already-used key are rejected. A native
profile/root write guards concurrent submission retries. This is transport replay
protection, not environmental duplicate detection. As in Task 1, a concurrent loser
may receive a runtime transaction error; retrying the same draft remains safe.

GPS uses browser getCurrentPosition directly from Jac callbacks: requested by click,
high accuracy, 12-second timeout, no cached position. Pending, denied, timeout,
unavailable, and unsupported states have text feedback. Coordinates remain blank
until supplied. Manual input is always available when not acquiring GPS. Location
confirmation locks the coordinate fields and GPS button; explicit Change location
unlocks them. A generation reference ignores GPS callbacks after unmount/change.
GPS requires a secure browser context (HTTPS/localhost); no reverse geocoding.

The UI has a report form, My Reports, empty/loading/error/success states, and authority
Incoming Reports using shared report cards. Failed submissions keep entered values.
A synchronous ref prevents double-submit; successful saves clear the draft. Cards
show ID, category, description/expandable long text, timestamp, status, coordinates,
location description, and an OpenStreetMap marker link. Maps load only on explicit
link navigation; no third-party map request is made merely by viewing private reports.

Image upload was inspected in installed Jac 0.37.23 guides (UploadFile + store and
browser file refs). Deferred because safe private uploads require content/size
validation, protected storage and serving. No upload endpoint or arbitrary URL input
was added; evidence_ref reserves the model boundary.

## Task 2 validation

- `jac check`: exit 0; compiler warnings remain, primarily JSX-name/generated setter
  warnings and explicit dynamic browser callback boundaries.
- `jac check --nowarn`: exit 0.
- `jac check tests --nowarn`: exit 0, both test modules checked.
- `JAC_TEST_JOBS=0 jac test`: exit 0, 23 passed (8 Task 1 + 15 Task 2).
- `git diff --check`: exit 0.
- Two existing `jac run` dev servers were found. No additional persistent server
  was started; the existing port 8000 App/8001 API were reused and health checked.
  `jac run --show` confirms the app configuration. Existing processes were preserved.

New tests cover creation/initial state/timestamps, list/get own, privacy of views,
anonymous rejection for all five report RPCs, cross-user denial, verified-org denial,
authority list/inspect, exact replay and conflicting replay, invalid inputs through
the API and core, all category/coordinate boundaries (including zero, NaN, infinity),
concurrent retries, and persistence after closing/reopening a native server fixture.

Task 1’s direct anonymous-core test now clears Jac’s request-root cache and shared
resolver on cleanup. It resolved the guest outside HTTP middleware; without cleanup,
Jac 0.37.23 retained that ID into the next isolated test database. No production
runtime internals were changed to fix test isolation.

Temporary browser accounts and their reports were removed after validation; no
sample data is seeded. Existing user data and server processes were preserved.

Actual Chrome browser automation passed: citizen registration/login; geolocation
permission denial; retry with granted permission and emulated coordinates; confirmation
lock; manual zero-coordinate fallback; server validation failure retains text/location;
two immediate submit events produce one report; report appears in My Reports; reload
and logout/login preserve saved reports; marker URL coordinates; no horizontal overflow
at 390px; no JavaScript exceptions. GPS success used Chrome’s emulated position, not
physical device GPS. Map link destination rendering and authority Incoming Reports UI
were not automated; authority APIs were exercised in Jac tests.

Manual follow-up: try physical-device GPS accuracy/permission settings over HTTPS,
open an OpenStreetMap marker, and review Incoming Reports as your configured authority.
Production deployment and multi-worker load remain unverified. No incidents,
deduplication/clustering, LLMs/agents, organization incident queue, cleanups, volunteers,
notifications, analytics, route planning, native mobile, or CLI were implemented.


## Task 2.5 — Role-based application shell

One reusable AppShell provides persistent desktop sidebar navigation, active-page
indication, account/profile controls, logout, refresh, breadcrumbs, skip-to-content,
and an accessible toggle/dismissible mobile drawer. The environmental visual system
is shared by all pages and the redesigned login/register screen. AppTheme embeds CSS
in Jac, following the existing scaffold's working style approach; Icon uses small
inline SVGs. No new dependencies, framework, backend, or runtime configuration.

Created navigation.jac (pure presentation policy), components/AppShell.jac,
AppTheme.jac, AuthPage.jac, Icon.jac, DateTime.jac, OverviewPages.jac,
OrganizationPage.jac, AccountPages.jac, ReportListPage.jac, PlannedPage.jac,
and tests/navigation_policy.jac with its annex. Modified frontend.jac and its
implementation, ReportPanel and its implementation (form only), ReportCard (date
formatting), tests/reports.test.jac (UI-state spoofing rejection), and these docs.
Core domain modules, endpoints, persistence schemas, auth helpers and authority
bootstrap configuration are unchanged.

Navigation derives from the server AccountView: organization:verify selects
Authority; otherwise an organization relationship selects Organization regardless
of pending/verified/rejected/suspended status; otherwise Citizen. resolve_page
falls back to Overview for unavailable authority pages. Pure presentation helpers
never mutate capability lists and cannot authorize a backend action.

Citizen: Overview with real report/submitted counts and recent observations;
Report Issue; My Reports; Cleanup Events placeholder; Profile. Organization:
Overview with actual organization/status/admin membership, Organization application
and pending edits, Incidents/Cleanup Events/Volunteers placeholders. Authority:
Overview with actual pending/incoming/verified counts, Incoming Reports,
Organization Review with verify/reject/suspend, Incident Review/Agent Activity
placeholders, Audit with latest decision per organization. This is current metadata,
not the full appended review log; full audit history is explicitly planned.

Profile is available from account controls in all workspaces. It exposes account
information and an advanced disclosure for the bootstrap root ID, plus organization
application and personal reporting actions. Official organization status is exactly
verified; rejection/suspension never render as verified. Unimplemented features
say "Not implemented yet"; no incident, agent, volunteer or cleanup statistics
were fabricated. Counts show loading/unavailable states on fetch failure.

The shell owns server-derived lists and view state, and passes typed callbacks to
page components. The existing GPS/report form remains mounted but hidden outside
Report Issue, retaining drafts/confirmation while navigating. Report categories,
validation, browser GPS, manual fallback, map links, submission retry keys and secure
Jac authentication are preserved. No separate frontend architecture was introduced.
Reload returns to Overview after recovering the session. Navigation state is not a
URL router; browser Back/Forward does not traverse views.

### Task 2.5 validation

- `jac check`: exit 0; compiler warnings remain (primarily generated setters/JSX and
  browser interop typing warnings).
- `jac check --nowarn`: exit 0.
- `jac check tests --nowarn`: exit 0.
- `JAC_TEST_JOBS=0 jac test`: exit 0, 28 passed (23 existing + 5 new).
- `git diff --check`: exit 0.
- Existing Jac development servers were reused; no additional persistent dev
  server was started. App at localhost:8000 / API localhost:8001 remained healthy.
  `jac run --show` verifies the existing application configuration.

New tests cover Citizen navigation, Organization relationship navigation, Authority
precedence/navigation, unavailable-page fallback without capability mutation, and
rejection of authority/capability fields supplied through client request state.

Actual Chrome checks: registration/login/logout/session recovery; Citizen pages
and counts; draft retention between Report Issue/My Reports; GPS denial and emulated
success; submission, map URL and persisted reports; organization application and
pending workspace; Profile personal tools; mobile drawer and no overflow at 390px.
Desktop/mobile screenshots were visually inspected.

Authority browser checks used the same compiled frontend with HTTP calls relayed to
an isolated native JacTestClient fixture (no second HTTP/dev server). They exercised
real Jac auth/core/graph operations: Authority navigation and real fixture counts,
Incoming Reports, verify/reject/suspend, Audit metadata, planned pages, and the
Organization verified/rejected/suspended views. No authority powers were granted to
live users for testing. Temporary live browser accounts/applications/reports were
removed; isolated fixture data was discarded.

Manual follow-up: review the layout in your preferred browsers/devices and try
physical GPS over HTTPS (automated GPS used emulation). Production deployment,
multi-worker load and exhaustive assistive-technology testing remain unverified.
Task 3 AI/incident intelligence, clustering, agents, cleanups, volunteers, and
notifications remain deferred. No Task 3 domain behavior was added.
