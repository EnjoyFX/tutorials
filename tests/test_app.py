import json
from threading import Thread
from types import SimpleNamespace
from urllib.error import HTTPError
from urllib.request import urlopen

import app
import pytest


def run_request(path):
    calls = []

    handler = SimpleNamespace(
        path=path,
        _respond=lambda status, payload: calls.append((status, payload)),
    )

    app.Handler.do_GET(handler)
    return calls


def run_server():
    try:
        server = app.HTTPServer(("127.0.0.1", 0), app.Handler)
    except PermissionError as exc:
        pytest.skip(f"loopback socket unavailable: {exc}")
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def stop_server(server, thread):
    server.shutdown()
    thread.join(timeout=2)
    server.server_close()


def get_json(url):
    with urlopen(url, timeout=2) as response:
        return response.status, response.headers, json.loads(response.read())


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


def test_http_server_returns_json_health_endpoint():
    server, thread = run_server()
    try:
        status, headers, payload = get_json(
            f"http://127.0.0.1:{server.server_port}/health"
        )
    finally:
        stop_server(server, thread)

    assert status == 200
    assert headers["Content-Type"] == "application/json"
    assert payload == {"status": "ok"}


def test_http_server_returns_json_404():
    server, thread = run_server()
    try:
        try:
            urlopen(f"http://127.0.0.1:{server.server_port}/missing", timeout=2)
        except HTTPError as exc:
            status = exc.code
            headers = exc.headers
            payload = json.loads(exc.read())
        else:
            raise AssertionError("Expected HTTP 404")
    finally:
        stop_server(server, thread)

    assert status == 404
    assert headers["Content-Type"] == "application/json"
    assert payload == {"error": "not found"}
