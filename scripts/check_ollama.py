"""Smoke-test the configured local LLM without starting the database or web app.

Run from the project root: backend/.venv/Scripts/python.exe scripts/check_ollama.py
"""

import asyncio
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from langchain_core.messages import HumanMessage, ToolMessage

from app.core.config import settings
from app.services.agents.chat_agent import ChatAgent
from app.services.llm.client import LLMClient


async def main() -> None:
    print(f"Endpoint: {settings.llm_base_url}; model: {settings.llm_model}")
    client = LLMClient()
    answer = await client.chat_text("Answer briefly in Chinese.", "Say that the local model is connected.")
    assert answer.strip(), "Text response is empty"
    print(f"Text: {answer}")

    result = await client.chat_json('Return only a JSON object with "ok": true.', {"request": "connection test"})
    assert result.get("ok") is True, f"JSON response failed: {result}"
    print(f"JSON: {result}")

    chunks = [chunk async for chunk in client.chat_text_stream(
        "Answer briefly in Chinese.", [{"role": "user", "content": "Say hello in one short sentence."}]
    )]
    assert chunks, "Streaming response is empty"
    print(f"Stream ({len(chunks)} chunks): {''.join(chunks)}")

    model = ChatAgent().model
    assert model is not None, "ChatAgent has no configured model"
    tool = {
        "type": "function",
        "function": {
            "name": "get_connection_status",
            "description": "Get the current local model connection status. Call this to check the connection.",
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
    }
    tool_model = model.bind_tools([tool])
    messages = [HumanMessage(content="Call get_connection_status to check the connection.")]
    response = await tool_model.ainvoke(messages)
    assert response.tool_calls, "Model did not request the status tool"
    assert response.tool_calls[0]["name"] == "get_connection_status", response.tool_calls
    print(f"Tool call: {response.tool_calls[0]['name']}")
    followup = await model.ainvoke([
        *messages, response,
        *[ToolMessage(content='{"connected": true}', tool_call_id=call["id"]) for call in response.tool_calls],
    ])
    assert followup.content, "Model did not answer after the tool result"
    print(f"Tool result answer: {followup.content}")
    print("All four local LLM checks passed.")


if __name__ == "__main__":
    asyncio.run(main())
