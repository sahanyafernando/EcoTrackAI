"""Root-scoped native test entry point; never imported by production main.jac."""
import from endpoints { account, create_report, all_reports, my_reports, get_report, apply,
    review, incident_intelligence_state, run_incident_intelligence }
import from tests.fixtures.intelligence_app { fixture_analysis, fixture_coordination }
