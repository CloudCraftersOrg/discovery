import os

import pytest

from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_build_is_not_forced_to_fail():
    assert not os.path.exists(os.path.join(os.path.dirname(__file__), "..", "FAIL_BUILD"))
