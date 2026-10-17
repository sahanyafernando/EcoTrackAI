# Task 1 implementation

Scope: Auth + RBAC + organization verification. Application and tests are Jac;
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

## Tests and observed validation

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

No environmental reports, GPS/maps, incidents, deduplication, AI agents, cleanups,
volunteer functionality, notifications, analytics, mobile application, CLI,
organization invitations/multiple memberships, resubmission, reactivation, or revoked
status. The unused generated MessageCard component remains, but the guestbook backend
and visible experience have been replaced. Local planning docs remain ignored.
