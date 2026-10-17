"""Real Jac HTTP dispatch, JWT identity, graph ACLs and persistence tests."""
import os;
import secrets;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

# any is confined to the runtime's JSON test transport.
def rpc(client: JacTestClient, name: str, body: dict[str, any] = {}) -> any {
    response = client.post("/function/" + name, json=body);
    assert response.ok, response.text;
    return response.json()["data"]["result"];
}

import from jaclang.testing.test { parametrize }
import from concurrent.futures { ThreadPoolExecutor }

def _anonymous_denied(endpoint: str) {
    with tempfile.TemporaryDirectory() as directory {
        client = JacTestClient.from_file("main.jac", base_path=directory);
        try {
            response = client.post("/function/" + endpoint, json={
                "name": "Test", "description": "Test", "organization_id": "unknown",
                "decision": "verified", "expected_revision": 1});
            assert response.status_code == 401, response.text;
        } finally { client.close(); }
    }
}

with entry {
    parametrize("anonymous protected access", ["account", "apply", "edit_organization", "organizations", "review"], _anonymous_denied);
}
import from core.domain { ensure_profile, apply_organization, review_application }

import from jaclang { JacRuntime as Jac }
