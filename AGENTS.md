# AGENTS.md — EcoTrack AI

This file guides coding agents working on EcoTrack AI **after the hackathon coding window officially begins**.

## Mission

Build an agentic environmental incident and cleanup coordination platform that turns noisy citizen reports into consolidated incidents, coordinates verified organizations, prevents duplicate response effort, and helps manage cleanup volunteers/resources.

## Read first

- `README.md`
- `docs/PRODUCT_OVERVIEW.md`
- `docs/FUNCTIONAL_REQUIREMENTS.md`
- `docs/RBAC.md`
- `docs/ARCHITECTURE.md`
- `docs/DATA_MODEL.md`
- `docs/AGENT_WORKFLOWS.md`
- `docs/JAC_80_PERCENT_STRATEGY.md`
- `docs/UI_UX_PLAN.md`
- `docs/TEST_PLAN.md`

If implementation and docs conflict, report the conflict instead of silently inventing a new architecture.

## Jac-first rule

Target **90%+ Jac source code**.

Prefer Jac for:
- domain models
- graph relationships
- persistence
- walkers/services
- auth/RBAC
- agent orchestration
- specialist agents
- agent tools
- web/mobile/CLI application logic where supported
- tests

Avoid parallel stacks such as FastAPI, Django, Express, Next.js or Python agent frameworks unless explicitly approved.

## Core distinction

Never collapse these concepts:

**Report** = one citizen observation/evidence.

**Incident** = one consolidated real-world environmental problem supported by one or more reports.

Duplicate reports remain linked as evidence.

## RBAC

Main trust domains:
- Citizen / Volunteer
- Environmental Organization
- Central Authority / Platform Administration

Organizations begin pending/unverified. They must not receive official incident-response powers until Central Authority verifies them.

A user-supplied ID is never authorization.

## Runtime agents

Use one orchestrator plus three specialists:
1. Coordinator Agent
2. Incident Intelligence Agent
3. Response Coordination Agent
4. Cleanup & Volunteer Agent

Do not create extra agents until MVP is complete.

Agents use structured tools and structured outputs. High-impact mutations use proposals/approval where documented.

## MVP order

1. Auth + RBAC
2. Organization registration + central verification
3. Citizen report submission
4. Incident duplicate/cluster detection
5. Authority cluster review + incident creation
6. Organization incident queue + lead-response ownership
7. Cleanup event + volunteer participation
8. Agent shortage/conflict replanning
9. Web polish
10. Mobile minimum flow
11. CLI minimum flow
12. Jac Hammer deployment
13. Demo hardening

Do not build rewards/analytics before the signature demo works.

## Security/privacy

- Do not expose private citizen data to unrelated organizations.
- Organizations see incident-level information needed for response.
- Central Authority receives broader audit/governance access.
- Keep agent decision logs.
- Never store plaintext passwords/API keys.
- Use environment variables for secrets.
- Never commit `.env`.

## Testing

Before claiming success:
- run Jac checks
- run tests
- run app
- verify RBAC with multiple accounts/roles
- verify duplicate report cluster flow
- verify one active lead organization per incident
- verify volunteer shortage/replanning flow
- verify narrow layout where practical

Never claim a test passed unless it actually ran.

## Signature demo invariant

**multiple reports → one incident → organization coordination → cleanup plan → changed condition → agent replan**
