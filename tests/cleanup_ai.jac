"""Task 7 tests reuse ordinary fixtures without importing peer test annexes."""
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
def setup_three(client: JacTestClient, password: str) -> dict[str, any] {
    setup = prepare(client, password); event = create(client, setup);
    for token in [setup["citizen"], setup["second"]] {
        client.set_auth_token(token); rpc(client, "join_cleanup", {"event_id": event["event_id"]});
    }
    assert client.register_user("citizen_c", password).ok;
    setup["third"] = client._auth_token or "";
    rpc(client, "join_cleanup", {"event_id": event["event_id"]});
    setup["event"] = event["event_id"];
    client.set_auth_token(setup["lead"]);
    return setup;
}
def plan(client: JacTestClient, event: str, mode: str = "positive", key: str = "") -> any {
    return rpc(client, "fixture_cleanup_ai", {"event_id": event, "request_id": key or secrets.token_urlsafe(24), "mode": mode});
}
