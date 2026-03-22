from pathlib import Path
from types import SimpleNamespace
import sys


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples" / "docker"))

import app  # noqa: E402


def run_request(path):
    calls = []

    handler = SimpleNamespace(
        path=path,
        _respond=lambda status, payload: calls.append((status, payload)),
    )

    app.Handler.do_GET(handler)
    return calls


def test_health_endpoint():
    assert run_request("/health") == [(200, {"status": "ok"})]


def test_root_endpoint_uses_environment(monkeypatch):
    monkeypatch.setenv("MESSAGE", "Hello from pytest!")
    monkeypatch.setenv("APP_VERSION", "9.9.9")

    calls = run_request("/")

    assert calls[0][0] == 200
    assert calls[0][1]["message"] == "Hello from pytest!"
    assert calls[0][1]["version"] == "9.9.9"
    assert calls[0][1]["hostname"]


def test_unknown_route_returns_404():
    assert run_request("/missing") == [(404, {"error": "not found"})]
