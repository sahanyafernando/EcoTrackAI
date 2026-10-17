"""Offline multi-agent orchestration integration tests."""
import os;
import secrets;
import tempfile;
import from jaclang.testing.testing { JacTestClient }
import from tests.fixtures.cleanup_ai_setup { rpc, AuthorityEnvironment, prepare, create }

def public_data(value: any) -> any {
    if isinstance(value, dict) { return {key: public_data(item) for (key, item) in value.items() if not key.startswith("_jac_")}; }
    if isinstance(value, list) { return [public_data(item) for item in value]; }
    return value;
}
def coordinate(client: JacTestClient, event: str, entity: str, mode: str = "positive", request: str = "") -> any {
    return rpc(client, "fixture_coordinator", {"event_type": event, "entity_id": entity,
        "request_id": request or secrets.token_urlsafe(24), "mode": mode});
}
