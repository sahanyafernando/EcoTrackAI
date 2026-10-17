"""Canonical browser/server report contract. No persistence, RPC or auth imports.

Import ReportView directly from contracts.report_views at every boundary.
UI annotations use import type; Jac generates RPC wire hydration classes.
"""

obj ReportView {
    has id: str,
        description: str,
        category: str,
        latitude: float,
        longitude: float,
        location_text: str,
        evidence_ref: str,
        submitted_at: str,
        status: str,
        created_at: str,
        updated_at: str,
        revision: int,
        source_type: str = "citizen",
        demo_dataset: str = "";
}
