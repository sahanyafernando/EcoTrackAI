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

## Task 3 — Incident Intelligence proposals

Task 3 supersedes the historical deferrals above for duplicate-candidate intelligence,
Incident Review and Incident Intelligence Agent activity. Confirmed Incidents and
human acceptance/rejection/splitting remain Task 4; original Report nodes stay intact.

Created:

- `core/intelligence.jac`: configuration, Haversine/pair signals, complete-link
  grouping, typed ClusterAssessment, guarded proposal writes, persistent
  IncidentClusterProposal/AgentRun/AgentDecision, authority-only views/index ACLs.
- `agents/tools.jac`: candidate-scoped current report context, deterministic
  distance, lexical overlap. Each tool rechecks capability and authorized scope.
- `agents/incident_intelligence.jac`: authority-triggered observe/analyze/reason/
  propose/verify/record pipeline and Jac-native `by llm` integration.
- `components/IntelligencePage.jac`: Incident Review and Agent Activity, reusing the
  existing shell/theme/report cards, date display and OpenStreetMap marker links.
- `tests/intelligence.jac`, its test annex, `tests/fixtures/intelligence_app.jac`
  and root-scoped `intelligence_test_app.jac`: offline native runtime fixtures.

Modified core/domain.jac only to add authority `agent:run_intelligence` and
`agent:read` capabilities. Added two protected RPCs in endpoints.jac, replaced the
Incident Review/Agent Activity placeholders in frontend.jac, and enabled the native
byLLM capability in jac.toml. Updated README and .env.example. Auth, organization
operations, report persistence, GPS, categories and existing navigation are retained.
The generated frontend/backend architecture is unchanged; no separate framework,
service, client SDK or agent framework was introduced.

Reports are loaded through existing authority-only report services. Jac scoring uses
Haversine radius, absolute submission-time window, explicit compatible categories,
location-text overlap and lexical description overlap. Candidate scores and all
thresholds are deterministic/configurable. Complete-link greedy groups require every
pair to meet those rules, preventing proximity-chain over-merging. Limits are the
200 newest eligible reports, 10 groups/run and 8 reports/group. Groups remain
disjoint; this bounded MVP does not enumerate all subsets or reassess a semantically
rejected subset. Report nodes are never merged or modified.

All candidate groups not already represented by an active proposal are compacted and
sent together in one typed Jac `by llm` request. Compact input contains descriptions,
categories, location text and Jac-computed pair distances, time differences,
category relationships, lexical overlaps and scores; it contains no reporter IDs or
report retrieval tool. Gemini is explicitly instructed to use those facts rather
than calculate geography/time. A batch must return exactly one typed assessment for
each exact unique candidate group ID. Jac validates every assessment and the complete
group-ID set before writing any proposals, then revalidates current report snapshots.
Negative `same_incident` assessments create no proposal. Report text is untrusted
evidence. Missing model configuration, provider failure or malformed output produces
a clean failed run; raw provider errors/private reasoning are not copied to audit.

IncidentClusterProposal uses its stable Jac graph ID as proposal_id, sorted distinct
report IDs, confidence, category/severity suggestions, public rationale, matching/
conflicting signals, computed pair signals, pending_review status, timestamps,
agent_run_id and revision=1. Canonical UUID5 graph identity plus existing-set checks
prevent multiple records for exactly the same report set; overlapping, different
sets remain proposals for future human review. Proposal writes revalidate snapshot
fields/status/category/time/distance against currently authorized reports. No report
ownership, content, status, timestamps or revision is changed.

AgentRun records requester internally, request replay key, model/configuration,
agent name, start/completion, status, report count, deterministic relationship count,
candidate group count, batched LLM request count, proposal count, and sanitized
error/summary. Public RunView omits requester and replay key. AgentDecision records run ID, decision type,
report IDs, computed pair signals, nullable model confidence, concise public rationale
and timestamp. Duplicates get an auditable skip without another model call. Empty
and singleton datasets complete without a provider. Earlier successful proposals
remain available if a later assessment fails.

Analysis is synchronous and serialized within one server process. A durable request
record is committed before external work so request replay returns its existing
result rather than calling a provider again. Jac 0.37.23 can retry a read-only request
when it first writes: the agent explicitly establishes the native Session writing
tier before creating its run. This preflight closes the initial transaction, opens
its read barrier and calls native ensure_writable_txn, letting any tier retry occur
before the run or model call. Tests cover this path on fresh runtime fixtures.
Runtime conflict/retry exceptions are rethrown rather than mistaken for model errors.
Process termination can leave an interrupted running record; recovery is explicit
with a new request. Distributed scheduling, worker/load guarantees and automatic
crash reconciliation are deferred.

Incident Review displays real latest-run statistics and persistent proposals,
confidence as a suggestion, public reasoning, matching/conflicting evidence, source
reports, coordinates, pairwise distances/time and map links. Task 4 actions are text
only, not active controls. Agent Activity displays persisted runs and expandable
decisions; additional agents/human approval events stay explicitly unimplemented.
No model runs on page load, reporting, login or refresh. Citizen/org requests cannot
run/read platform intelligence, even with forged navigation/capability state.

### Original Task 3 tests and validation

Original Task 3 tests cover Haversine identity/symmetry/known meters/dateline,
candidate filtering, complete-link grouping, proposal persistence, replay behavior,
unchanged reports, report reference validation, model failure, authority RBAC,
production RPC isolation, configuration, missing provider configuration, empty and
singleton datasets. No provider key or live model is needed.

### Task 3 deterministic scoring and batched semantics follow-up

Candidate relationships now require spatial/time bounds, same or explicitly related
categories, text overlap, and a combined score threshold. Location and description
overlap thresholds and the combined minimum score are server-configurable. The
complete-link constraint remains in place. Model input is a compact list of all
candidate groups with Jac-computed pair facts; no tools permit model-side report
retrieval or distance/time calculations. One Gemini/byLLM request returns one
`ClusterAssessment` per group. The complete response is validated for exact unique
group IDs and all fields before any proposal creation. Synthetic 16-report coverage
asserts four deterministic groups, one MockLLM batch invocation, four validated
proposals, and unchanged source reports. Unit/integration coverage also checks
category compatibility, category equality without textual evidence, negative and
invalid AI output, and run observability. Live model setting remains the configured
Gemini 3.8 Flash model; offline tests use MockLLM only.

The test entry point is deliberately at project root because the installed runtime's
prepared-module loader misresolved transitive imports from a nested entry. Production
main.jac does not import it; production endpoint registry was inspected and contains
only existing RPCs plus the two new protected intelligence RPCs.

Actual Chrome automation used the same frontend and an isolated native JacTestClient
graph, relaying HTTP calls without another persistent HTTP/dev server. It exercised
authority-triggered offline MockLLM analysis; three nearby report references/maps and
distant fourth-report exclusion; persisted proposal and real counters; expandable
run/decision activity; duplicate proposal skip; reload/session recovery; Citizen
navigation; mobile 390px no overflow; no JavaScript exceptions. Desktop/mobile
screenshots were visually inspected. Temporary isolated users/reports/proposals were
discarded. No fake production data, live authority changes or seeded proposals.

Live provider connectivity, provider-specific output quality and the documented
four-citizen live demonstration still require manual testing with server environment
configuration. Physical-device GPS and deployment/load checks from earlier milestones
also remain manual. No confirmed Incident, cluster approval/rejection/splitting,
organization response, other runtime agents, cleanup, volunteer, notifications,
analytics, mobile app or CLI was implemented.

Final Task 3 validation on Jac 0.37.23:

- `jac install`: exit 0; native byLLM hosted-provider dependencies installed.
- `jac check`: exit 0, 1 passed; 498 compiler warnings remain, including existing
  JSX/generated-setter and dynamic frontend typing warnings.
- `jac check --nowarn`: exit 0, 1 passed.
- `JAC_TEST_JOBS=0 jac test`: exit 0, **45 passed in 42.51s** (28 existing + 17 new),
  with no paid/live model calls.
- `git diff --check`: exit 0.
- Existing `jac run` processes were preserved; no new persistent dev server was
  launched. `jac run --show`: exit 0, existing full-stack app configuration;
  App localhost:8000 returns HTTP 200; the new protected intelligence RPC on
  localhost:8001 returns HTTP 401 for an anonymous probe.
- Final Chrome fixture run: passed the offline browser scenarios above after the
  final UI changes; updated screenshots visually inspected.
- Source mix (owned tracked + new nonignored source, excluding generated runtime,
  dependencies, docs/config): **35 Jac files / 2,360 lines; no Python/JS/TS/CSS source
  files**. Styles remain embedded in the existing Jac theme. The project remains
  comfortably above the 80% competition requirement and internal 90% Jac target.

## Task 3 follow-up — optional synthetic dataset

Added core/demo_dataset.jac and tests/demo_dataset.jac with its annex. Extended
Report/ReportView with default `source_type="citizen"` and `demo_dataset=""`;
normal submission signatures/ownership/auth remain unchanged and cannot assign these
fields. Added authority `demo:manage`, three protected demo RPCs, opt-in controls in
Incident Review, source-count/member-ID visibility on proposals, ReportCard Demo
badges, and refresh callbacks so Incoming Reports reloads after maintenance. Updated
.env.example and README. The test-only semantic fixture gained a generic offline
MockLLM mode for arbitrary candidate groups. All added application/test logic is Jac.

**Unchanged byte-for-byte during this follow-up:** agents/incident_intelligence.jac,
agents/tools.jac, core/intelligence.jac. Their checksums were compared before/after.
The production agent has no fixture membership, expected grouping or dataset-specific
analysis logic. Seeding creates no proposals and never invokes a model.

`ECOTRACK_ENABLE_DEMO_SEED=true` explicitly enables loading/clearing; unset/false
blocks both operations in core and hides both buttons. Existing demo reports remain
badged/visible if the flag is later disabled. Status and mutation RPCs still require
Central Authority capabilities; anonymous/citizen/applicant requests are rejected.
No credentials, synthetic accounts or independent authentication system are created.

The fixed `incident-intelligence-demo-v1` manifest owns 16 authority-managed synthetic
Report nodes under the authenticated authority graph, indexed by the normal private
IncomingReport relationship. Uniform source_type=demo_seed/demo_dataset provenance
identifies every fixture. The internal reporter reference is synthetic, not another
person's account; these nodes do not appear in the authority's My Reports. A canonical
manifest identity and existing-dataset lookup make loading idempotent, including
across fixture-server reopen. Subsequent loads return “Demo dataset already loaded.”

A flat Jac fixture generator contains four observations each for canal-side illegal
dumping, blocked drain/local flooding, stream water pollution, and overflowing public
bins. All landmarks/observations are fictional Sri Lankan-style examples. Descriptions
vary naturally and share ordinary vocabulary. Distances within each intended group
are approximately 20–90m and submission times within about 21 minutes; all 16 span
105 minutes, with locations several kilometres apart between groups. Expected group
memberships are asserted only in tests, not fields offered to the production agent.

The normal analysis pipeline sees all submitted reports, synthetic and genuine.
Four proposals are an evaluation expectation at default filters, never a production
constant/result. Incoming Reports keeps all 16 original observations after proposals
are generated. Incident Review shows actual dataset/report/proposal counts, every
proposal's source count/IDs, confidence, suggested category/severity and public
rationale/signals. Model/provider configuration is still required for live analysis.

Cleanup builds and validates its whole deletion plan before deleting anything. It
uses manifest IDs plus provenance and native ownership checks, removes demo-only
proposals/decisions, and removes only safely attributable demo-only runs. Mixed or
unattributable run history is preserved. If a proposal/decision includes genuine or
unrelated reports, or another authority owns related records, the whole cleanup is
refused without partial deletion. The same loading authority must clear the dataset;
no native ACL was widened to permit deleting another authority's records. Repeated
clear is harmless. Reload creates fresh report IDs so retained historical references
cannot resolve to newly generated observations. Real reports are never deletion
targets. Maintenance shares the existing process-local analysis lock and commits
before releasing it. Multi-worker deployment guarantees remain outside this scope.

Seven offline tests cover default-off gating and roles; exact 16/provenance/category/
state and idempotency across persistence reopen; client provenance-spoof rejection;
all within-group distances/candidate relationships and geographically excluded
cross-group pairs (including when categories are made equal); normal agent + native
MockLLM producing four proposals without report mutation; pure-demo cleanup and fresh
reload IDs; genuine report/mixed-run preservation; refusal for mixed proposals; and
cross-authority cleanup denial. No live provider is required by automated tests.

Follow-up validation:

- `jac check --nowarn`: exit 0, 1 passed (7.62s).
- `JAC_TEST_JOBS=0 jac test`: exit 0, **52 passed in 59.17s** (45 existing + 7 new),
  no paid/live LLM calls.
- `git diff --check`: exit 0.
- Fresh `jac build --as client -o /tmp/ecotrack-demo-client-build`: exit 0, client
  bundle built successfully. The runtime writes client output under .jac/client/dist.
  Existing dev-server incremental compiler retained stale ReportView interfaces
  and kept restoring its cached error overlay. The fresh build passes; final
  browser validation used this built bundle directly, with an explicit absence-of-
  overlay assertion, without starting another server. Restart the existing dev
  process when setting the demo flag to refresh its in-memory compiler state.
- Actual Chrome checks of the freshly built client passed against isolated native
  Jac graph/auth plus offline MockLLM: hidden default-off controls, explicit enable,
  load/repeat-load, exactly 16
  Incoming Demo badges, four normal-pipeline proposals with source IDs/counts, all
  original reports retained afterward, disable/hide, clear refreshing both pages,
  repeated load/clear, session recovery/persistence, mobile 390px no overflow, no
  JavaScript exceptions. Desktop/mobile screenshots were visually inspected.
  Temporary fixture data was discarded; no live database was seeded during work.
- Agent/tools/clustering-core before/after checksums match. Existing development
  servers were reused, with no additional persistent jac run process started.

Manual follow-up: export the opt-in flag and existing authority root ID, configure
provider model/key for live analysis, restart your existing server, login as the
same authority for load/analyse/clear. README contains exact shell commands. Live
provider quality remains untested by automation; approximately four proposals is
an expectation, not a guaranteed result. Task 4 remains unimplemented.

### ReportView client-bundle correction

`contracts/report_views.jac` is now the single source declaration of the report
view contract. Server services, RPC endpoints, intelligence tools and tests import
it directly. Frontend components and the application import that same contract
with `import type`; implementation annexes inherit the binding and retain typed
report callbacks and lists. The persistent Report node remains in `core/reports.jac`.

The earlier cache-only explanation above was incomplete: importing ReportView
through endpoint re-exports and server-domain modules produced inconsistent client
type identities. A regular runtime import of the extracted contract also collided
with Jac's generated RPC hydration class (`Identifier "ReportView" has already
been declared`). Direct type-only UI imports fix both boundaries without changing
generated code, weakening types, or bypassing authorization. Demo provenance fields
remain part of this shared contract; there is no component-local ReportView.

Regression coverage checks the server/RPC/tool type identity and serialized contract
path. The mixed genuine/demo cleanup fixture now names the same physical landmark,
so it satisfies the current location/content candidate filter and continues testing
refusal to delete mixed evidence. No clustering or cleanup safety rule was relaxed.

Validation after this correction:

- `jac check --nowarn`: exit 0, 1 passed in 8.23s.
- Focused demo tests: exit 0, 7 passed in 33.04s.
- `JAC_TEST_JOBS=0 jac test`: 58 passed in 70.24s, no live provider calls.
- `jac build --as client`: exit 0, bundle built in 4.3s.
- `git diff --check`: exit 0.
- Existing `jac run` process reused; app, frontend and Intelligence page modules
  return HTTP 200 with no client diagnostic marker. `jac run --show` exits 0.
  Interactive browser flows and live-model analysis were not rerun for this fix.

## Task 4 — Central Authority Incident confirmation

Implemented a minimal persistent `Incident` and separate `HumanIncidentReview`
audit node in `core/incidents.jac`, with client-safe views in
`contracts/incident_views.jac`. Incidents contain category, severity, confirmed
status, source report IDs/proposal ID, timestamps, confirming root and revision.
Only authority capabilities permit reviewing proposals or listing this private data.
`list_confirmed_incidents()` provides the domain entry point for later integration;
organization access/response is not enabled yet.

The only review transitions are `pending_review → confirmed/rejected`. Both require
the current proposal revision and record reviewer/time/result/revision. Confirmation
creates a canonical Incident identity derived from the proposal, increments its
revision, and atomically commits Incident/proposal/human audit. Repeated/stale
reviews fail. Missing/duplicate report references or invalid category/severity
cannot be confirmed. No source Report is changed or deleted.

Incident Review now offers Confirm Incident/Reject Proposal, reviewed status and
metadata, and a persisted Confirmed Incidents section. Agent Activity displays human
decisions separately from AgentDecision. Split is explicitly unimplemented. Existing
type-only UI contract imports are retained. The model receives no confirmation tool;
the shared process-local lock also blocks review from an active model assessor.
Analysis skips already reviewed report sets instead of overwriting human decisions.
Demo cleanup refuses any reviewed proposal to retain human audits and evidence.

Six focused offline tests exercise real native auth/graph/proposal creation,
cross-authority confirmation, exact source IDs and unchanged reports, duplicate and
stale review protection, rejection/no reactivation, persistence across reopening,
anonymous/Citizen/applicant/verified-organization denials, injected model confirmation
denial and reviewed-demo preservation. No live provider calls are made.

Validation:

- `jac check --nowarn`: exit 0, 1 passed in 9.14s.
- Focused Task 4 tests: exit 0, 6 passed in 19.43s.
- `JAC_TEST_JOBS=0 jac test`: exit 0, 64 passed in 66.77s.
- `git diff --check`: exit 0.
- `jac build --as client`: exit 0, bundle built in 3.4s.
- Restarted the existing development process with its environment preserved after
  an incremental compiler error about server-only imports. Fresh `jac run` compiled
  server/client artifacts and reached Server ready at App :8000 / API :8001.
  No second development server was started.

Earlier iterations caught a missing brace/unsupported transaction-interface method,
then test collection imported peer test annexes and source edits raced preparation.
These were corrected; the final isolated and full runs above passed.

Manual browser follow-up: login as Authority, inspect existing proposals, confirm
one and reject another, refresh/relogin, inspect Confirmed Incidents and human
activity, and verify Incoming Reports/My Reports still show every source. Browser
click flows and live-model quality were not automated for Task 4. No new environment
variables are required. Split/merge/reopen/override, organization response, cleanups,
volunteers and Task 5 remain deferred; multi-worker concurrency is not certified.
