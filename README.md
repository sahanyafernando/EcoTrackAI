# EcoTrack AI

Jac-powered environmental coordination. **Implemented: authentication, RBAC, organization verification,
citizen environmental reports with GPS/manual coordinates, and a role-aware
application shell, authority-triggered Incident Intelligence proposals, and human
Incident confirmation/rejection (Tasks 1–4).**

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
validation results, and remaining manual checks. Organization response, additional agents,
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

Related-report intelligence is implemented separately in Task 3 below.
Organization response remains deferred.

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
  Organization Review, Incident Review, Agent Activity, Audit.
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

## Incident Intelligence (Task 3)

**Report ≠ Incident.** Only Central Authority can run intelligence or read proposals
and agent audit records. Citizens and organization accounts retain their existing
permissions. A model can suggest a report cluster, category and severity; it cannot
change reports, verify organizations, promote users or create a confirmed Incident.
Central Authority can confirm or reject proposals as described in Task 4 below.
Splitting proposals remains deferred.

Install the native byLLM capability's hosted-provider dependencies with `jac install`.
Choose a supported provider in the **server environment**, for example:

```bash
export BYLLM_DEFAULT_MODEL='gemini/gemini-3.8-flash'
export GOOGLE_API_KEY='your-provider-key'
# Keep your existing ECOTRACK_AUTHORITY_ROOT_IDS configuration.
jac run
```

Use your provider's available model ID. This integration also accepts OpenAI
`gpt-...` / `openai/...` models with `OPENAI_API_KEY`, and `anthropic/...` with
`ANTHROPIC_API_KEY`. Gemini's `GEMINI_API_KEY` alias is also accepted by the installed
runtime. Provider keys stay on the server and are never copied into application nodes.
An `.env.example` file is a template, not an automatic environment loader.
See the [official byLLM reference](https://www.jac-lang.org/reference/plugins/byllm/).
No live model is needed for ordinary authentication, reports or organization flows.
Missing configuration and provider/output failures produce a persisted failed run,
not fabricated proposals. Candidate-free runs finish without contacting a model.

Jac preprocessing uses Haversine distance, absolute submission-time proximity,
same or explicitly compatible categories, location-text overlap and lexical
description overlap. A pair must be geographically and temporally within bounds,
have compatible categories, meet at least one configurable text-overlap threshold,
and meet the combined deterministic score. Category equality alone never creates
a relationship. The built-in compatibility mapping is limited to closely related
waste/damage categories and is symmetric. Defaults:

| Server variable | Default | Accepted range |
| --- | --- | --- |
| `ECOTRACK_DUPLICATE_RADIUS_METERS` | 250 | >0–10,000 meters |
| `ECOTRACK_DUPLICATE_TIME_WINDOW_HOURS` | 72 | >0–8,760 hours |
| `ECOTRACK_DUPLICATE_LOCATION_OVERLAP` | 0.25 | 0–1 |
| `ECOTRACK_DUPLICATE_DESCRIPTION_OVERLAP` | 0.20 | 0–1 |
| `ECOTRACK_DUPLICATE_MIN_SCORE` | 0.50 | 0–1 |
| `ECOTRACK_CLUSTER_CONFIDENCE_THRESHOLD` | 0.70 | 0–1 |

Analysis considers the newest 200 eligible reports, at most 10 candidate groups,
and at most 8 reports per group. Complete-link greedy grouping requires **every pair**
to meet the configured spatial, temporal, category and text-evidence rules; it does
not follow arbitrarily long proximity chains. It creates candidate groups only and
never merges or changes Report nodes. Groups are disjoint per run; semantic rejection
does not search every possible subset. Existing proposals with exactly the same
sorted report set skip semantic review.

Jac sends all unreviewed candidate groups together in one native byLLM invocation.
Each compact group includes report IDs, descriptions, categories, location text and
Jac-computed pair distances, time differences, category relation, lexical overlaps
and compatibility scores. Gemini does not retrieve report context or calculate
distance/time. It returns one typed `ClusterAssessment` per candidate group:
candidate group ID, same-incident decision, confidence, concise public rationale,
matching/conflicting signals, and suggested category/severity. Jac validates the
complete batch—including exact, unique group IDs and every structured field—before
creating any proposal, then revalidates real report references/snapshots before
writing `pending_review` proposals. A negative assessment creates no proposal.
Confidence is a suggestion, not verified truth.

Run observability includes raw reports examined, deterministic candidate
relationships, candidate groups, batched LLM request count and proposals created.

Open **Authority → Incident Review → Run Incident Intelligence**. The page displays
real run counters, persisted proposals, source reports, distances, and individual
OpenStreetMap marker links. No third-party map loads automatically. **Agent Activity**
shows runs and concise decision records. These records include configuration/model,
times, status, candidate signals and public rationale; private internal reasoning is
not stored by the application. Report ownership, status and revisions remain unchanged.
Request IDs prevent transport retries from replaying paid work. Analysis is serialized
within each server process; deployment-wide concurrency/load is not certified.
If the process terminates mid-run, its last record may remain `running`; inspect
activity and explicitly start a new request after recovery. No background scheduler
or automatic retry of costly analysis is installed.

For a live demonstration, create reports from three separate citizen accounts near
one bridge, for example `(6.9271,79.8612)`, `(6.9274,79.8612)` and
`(6.9277,79.8612)`, all `illegal_dumping` within 72 hours:

- “Large garbage pile beside the canal near the bridge”
- “Someone dumped plastic and rubbish next to the canal bridge”
- “Waste dumped beside same bridge and waterway”

From a fourth account submit `blocked_drain` several kilometres away, for example
`(6.9900,79.9000)`. Login as configured Authority and run analysis. The first three
can yield a high-confidence proposal; the fourth must be excluded deterministically.
Model output is not guaranteed. Inspect signals and source observations; do not treat
it as authority confirmation. Reports are never seeded automatically; the optional
synthetic dataset is described below.

Normal `JAC_TEST_JOBS=0 jac test` uses injected assessments and native `MockLLM`,
including real structured-output parsing for a single batched multi-group response.
It verifies one model invocation for the four deterministic demo groups and never
requires provider keys or paid calls. `intelligence_test_app.jac` is an isolated test
entry point; production `main.jac` does not import it or expose fixture controls.

## Optional synthetic demo dataset

Demo loading/clearing is **disabled by default**. To demonstrate the existing agent
with 16 observations, configure the server before starting it (restart an existing
server with these exports rather than launching another copy):

```bash
export ECOTRACK_ENABLE_DEMO_SEED=true
export ECOTRACK_AUTHORITY_ROOT_IDS='your-existing-authority-account-root-id'
export BYLLM_DEFAULT_MODEL='gemini/gemini-3.8-flash'
read -rsp 'Google provider API key: ' GOOGLE_API_KEY; echo
export GOOGLE_API_KEY
jac run
```

The model/key are needed for live analysis, not for loading or viewing the dataset.
Use the same alternative provider settings documented above if appropriate. These
are shell environment settings; copying `.env.example` does not load them automatically.

Login as that authority and open **Incident Review → Load Demo Dataset**. The page
shows **16 Demo Reports Loaded** from persisted state. Repeating Load returns
“Demo dataset already loaded.” Then open **Incoming Reports** to see all 16 **Demo**
badges, descriptions, categories, coordinates, timestamps and statuses. Existing
Citizen reports remain visible alongside them. Return to Incident Review and click
**Run Incident Intelligence**: Jac preprocessing typically reduces the 16 observations
to four complete-link candidate groups, followed by one batched Gemini semantic
request for those groups. This can produce approximately four real persisted
**Cluster Proposals**, with actual counts and source IDs. No proposals
or expected memberships are seeded. The original 16 reports remain visible afterward.

The fictional Sri Lankan-style observations cover canal-side illegal dumping,
a blocked roadside drain/flooding near a tea shop, stream contamination at bathing
steps, and overflowing public waste bins by a market bus halt. Each has four natural
wordings and appropriate category. Within-group distances are approximately 20–90m;
locations are several kilometres apart between groups. Submission times span less
than two hours. These are synthetic examples, not allegations about actual locations.

Reports use `source_type="demo_seed"`, `demo_dataset="incident-intelligence-demo-v1"`.
Ordinary reports default to `source_type="citizen"`, with no dataset ID; clients
cannot set provenance through the normal report endpoint. Fixtures live under a
platform dataset node owned by the loading authority, use a synthetic reporter
reference, and do not create users or appear in that authority's personal My Reports.
All 16 share the same provenance metadata; no case labels or expected cluster IDs
are passed to the production agent.

**Clear Demo Dataset** is available to the authority that loaded it while the flag
is enabled. It removes only manifest-identified synthetic reports, demo-only
proposals/decisions and safely attributable demo-only runs. Genuine reports and
mixed/unattributable run history are retained. Cleanup refuses the whole operation
before deleting anything if a proposal/decision mixes synthetic and genuine evidence
or another authority owns related records. Use the same authority account for
load/analyse/clear, preferably in an isolated demo database. Clearing and loading
again creates fresh report IDs, preserving the meaning of retained historical IDs.
Disabling the flag hides controls and blocks load/clear; it does not hide or delete
already loaded reports or their Demo badges.

This facility shares the existing per-process analysis lock, so local analysis and
dataset maintenance cannot overlap. Multi-worker deployment remains outside the
current validation scope.

## Authority Incident confirmation (Task 4)

Open **Authority → Incident Review**, inspect the proposal's reports, deterministic
evidence, confidence, category and severity, then choose **Confirm Incident** or
**Reject Proposal**. Only a `pending_review` proposal can be reviewed, with its
current revision. Confirmation creates exactly one persistent `confirmed` Incident
containing the source report IDs, category/severity, confirmation time/reviewer,
source proposal ID, timestamps and revision. Rejection creates no Incident.
Source Reports remain unchanged and visible in Incoming Reports and My Reports.

The page shows reviewed statuses and a **Confirmed Incidents** list. Agent Activity
shows human review records separately from agent decisions. Server capabilities
enforce review/confirmation; Citizen and Organization accounts cannot review or
list this private authority data. Analysis cannot perform confirmation or recreate
the same reviewed report set. Repeated/stale review requests fail without a second
Incident. The native transaction commits the Incident, proposal and human review
together; a canonical Incident ID and proposal revision protect duplicate writes.
The existing process-local analysis lock also serializes review with analysis and
demo maintenance. Multi-worker load has not been certified.

**Demo cleanup refuses reviewed proposals**, including rejected proposals, to retain
human audit decisions and confirmed Incident evidence. Use a fresh isolated demo
database for another end-to-end rehearsal after confirmation.

Split/merge/edit/reopen workflows, organization response coordination, cleanup
events and volunteers remain deferred. No new environment configuration is needed.
