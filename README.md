# EcoTrack AI

Jac-powered environmental coordination. **Task 1 implements authentication, RBAC,
organization applications, and Central Authority verification only.**

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
   account, login, and copy its **Account root** from the dashboard.
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
validation results, and remaining manual checks. Reports, incidents, agents,
cleanups, volunteering, maps, notifications, analytics, mobile, and CLI are deferred.
