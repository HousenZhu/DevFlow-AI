import json

import httpx
import pytest

from app.core.config import settings
from app.services.agents.chat_agent import ChatAgent
from app.services.llm.client import LLMClient


@pytest.mark.asyncio
@pytest.mark.parametrize("mode", ["text", "json", "stream"])
async def test_ollama_compatible_requests(monkeypatch, mode) -> None:
    monkeypatch.setattr(settings, "llm_api_key", "ollama")
    monkeypatch.setattr(settings, "llm_base_url", "http://localhost:11434/v1/")
    monkeypatch.setattr(settings, "llm_model", "devflow-qwen3:8b")
    monkeypatch.setattr(settings, "llm_timeout_seconds", 180.0)
    monkeypatch.setattr(settings, "llm_reasoning_effort", "none")
    monkeypatch.setattr(settings, "prompt_cache_enabled", False)

    def handle(request: httpx.Request) -> httpx.Response:
        assert str(request.url) == "http://localhost:11434/v1/chat/completions"
        assert request.headers["Authorization"] == "Bearer ollama"
        assert request.extensions["timeout"]["read"] == 180.0
        payload = json.loads(request.content)
        assert payload["model"] == "devflow-qwen3:8b"
        assert payload["reasoning_effort"] == "none"
        assert "prompt_cache_key" not in payload
        if mode == "stream":
            assert payload["stream"] is True
            return httpx.Response(
                200,
                headers={"content-type": "text/event-stream"},
                text='data: {"choices":[{"delta":{"content":"连接成功"}}]}\n\ndata: [DONE]\n\n',
            )
        if mode == "json":
            assert payload["response_format"] == {"type": "json_object"}
            content = '{"ok": true}'
        else:
            content = "连接成功"
        return httpx.Response(200, json={"choices": [{"message": {"content": content}}]})

    original_client = httpx.AsyncClient
    monkeypatch.setattr(
        "app.services.llm.client.httpx.AsyncClient",
        lambda **kwargs: original_client(transport=httpx.MockTransport(handle), **kwargs),
    )
    client = LLMClient()
    if mode == "json":
        assert await client.chat_json("Return JSON", {"question": "test"}) == {"ok": True}
    elif mode == "stream":
        chunks = [chunk async for chunk in client.chat_text_stream("test", [{"role": "user", "content": "test"}])]
        assert "".join(chunks) == "连接成功"
    else:
        assert await client.chat_text("test", "test") == "连接成功"


def test_cloud_requests_keep_default_reasoning_behavior(monkeypatch) -> None:
    monkeypatch.setattr(settings, "llm_reasoning_effort", None)
    monkeypatch.setattr(settings, "prompt_cache_enabled", True)
    monkeypatch.setattr(settings, "prompt_cache_key", "cache-key")
    monkeypatch.setattr(settings, "prompt_cache_retention", None)
    assert LLMClient()._model_kwargs() == {"prompt_cache_key": "cache-key"}


def test_chat_agent_uses_local_timeout_and_reasoning(monkeypatch) -> None:
    monkeypatch.setattr(settings, "llm_api_key", "ollama")
    monkeypatch.setattr(settings, "llm_base_url", "http://localhost:11434/v1")
    monkeypatch.setattr(settings, "llm_model", "devflow-qwen3:8b")
    monkeypatch.setattr(settings, "llm_timeout_seconds", 180.0)
    monkeypatch.setattr(settings, "llm_reasoning_effort", "none")
    monkeypatch.setattr(settings, "prompt_cache_enabled", False)
    captured = {}

    def create_model(**kwargs):
        captured.update(kwargs)
        return object()

    monkeypatch.setattr("app.services.agents.chat_agent.ChatOpenAI", create_model)
    assert ChatAgent().model is not None
    assert captured["base_url"] == "http://localhost:11434/v1"
    assert captured["api_key"] == "ollama"
    assert captured["model"] == "devflow-qwen3:8b"
    assert captured["timeout"] == 180.0
    assert captured["reasoning_effort"] == "none"
    assert captured["model_kwargs"] == {}
