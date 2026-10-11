#!/usr/bin/env python3
"""Loopback-only BYOK fixture for Simulator UI and translation-extension checks.

Run: python3 Scripts/mock_model_server.py --port 0 --log build/mock-requests.jsonl
Use the printed base URL, model ``copilot-test-model``, key ``local-simulator-key``,
and enable the app's explicit loopback HTTP option. No external model is called.
Request logs contain role counts and recognized public fixture text, never keys,
headers, custom prompts, or arbitrary submitted text.
"""

from __future__ import annotations

import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DUMMY_KEY = "local-simulator-key"
MODEL = "copilot-test-model"
SOURCE = "Good design makes complex things simple."
PUBLIC_QUESTIONS = {"What does complex mean?", "Make it more natural.", "What does simple mean?"}
RESPONSES = (
    "优秀的设计让复杂的事情变得简单。",
    "complex 的意思是“复杂的”。这里强调优秀设计帮助人们轻松理解复杂内容。",
    "自然一点可以译为：“好的设计，能把复杂的事变简单。” 这延续了前面的译文和词义说明。",
)


def answer_for_turn(turn: int) -> str:
    if turn < len(RESPONSES):
        return RESPONSES[turn]
    return f"第 {turn} 次追问：我保留了原文、译文和前面的 {turn - 1} 轮问答。"


def inspect_context(protocol: str, body: dict) -> tuple[list, list[str]]:
    errors = []
    if protocol == "responses":
        turns = body.get("input", [])
        prompt = body.get("instructions")
        if body.get("store") is not False:
            errors.append("Responses store must be false")
    else:
        turns = body.get("messages", [])
        if protocol == "chat":
            prompt = turns[0].get("content") if turns and isinstance(turns[0], dict) else None
            if not turns or turns[0].get("role") != "system":
                errors.append("Chat requires a system prompt")
            turns = turns[1:]
        else:
            prompt = body.get("system")
            if not isinstance(body.get("max_tokens"), int):
                errors.append("Anthropic max_tokens is missing")
    if not isinstance(prompt, str) or not prompt.strip():
        errors.append("System prompt is empty")
    if body.get("stream") is not False:
        errors.append("Fixture expects non-streaming request")
    if not isinstance(turns, list) or not turns or len(turns) % 2 != 1:
        return [], errors + ["Context must have an odd number of turns ending in user"]
    for index, message in enumerate(turns):
        if not isinstance(message, dict):
            errors.append(f"Turn {index} is not a message")
            continue
        if message.get("role") != ("user" if index % 2 == 0 else "assistant"):
            errors.append(f"Turn {index} has an unexpected role")
        text = message.get("content")
        if not isinstance(text, str) or not text.strip():
            errors.append(f"Turn {index} is empty")
        if index % 2 == 1 and text != answer_for_turn(index // 2):
            errors.append(f"Prior assistant turn {index} was not preserved")
    return turns, errors


class FixtureServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], log_path: Path):
        super().__init__(address, FixtureHandler)
        self.request_count = 0
        self.log_path = log_path
        self.log_lock = threading.Lock()
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

    def record(self, record: dict) -> None:
        with self.log_lock:
            self.request_count += 1
            record["request"] = self.request_count
            line = json.dumps(record, ensure_ascii=False)
            with self.log_path.open("a", encoding="utf-8") as file:
                file.write(line + "\n")
            print(line, flush=True)


class FixtureHandler(BaseHTTPRequestHandler):
    server: FixtureServer

    def log_message(self, format: str, *args) -> None:
        pass  # Never emit headers, raw request paths, or submitted content.

    def reply(self, status: int, payload: dict) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path == "/health":
            self.reply(200, {"ready": True, "requests": self.server.request_count})
        else:
            self.reply(404, {"error": {"message": "Unknown fixture endpoint"}})

    def do_POST(self) -> None:
        protocols = {"/v1/chat/completions": "chat", "/v1/responses": "responses", "/v1/messages": "anthropic"}
        protocol = protocols.get(self.path)
        if protocol is None:
            self.reply(404, {"error": {"message": "Unknown fixture endpoint"}})
            return
        key = self.headers.get("x-api-key") if protocol == "anthropic" else self.headers.get("Authorization", "").removeprefix("Bearer ")
        if key != DUMMY_KEY:
            self.reply(401, {"error": {"message": "Use the documented local dummy key"}})
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 1_048_576:
                raise ValueError("Invalid request size")
            body = json.loads(self.rfile.read(size))
            if not isinstance(body, dict):
                raise ValueError("Request must be an object")
            turns, errors = inspect_context(protocol, body)
        except (ValueError, AttributeError, TypeError):
            self.reply(400, {"error": {"message": "Malformed fixture request"}})
            return
        if protocol == "anthropic" and self.headers.get("anthropic-version") != "2023-06-01":
            errors.append("Anthropic version header is incorrect")
        model = body.get("model")
        if model != MODEL:
            errors.append("Use copilot-test-model for this fixture")
        roles = [turn.get("role", "invalid") if isinstance(turn, dict) else "invalid" for turn in turns]
        user_turns = [turn for turn in turns if isinstance(turn, dict) and turn.get("role") == "user"]
        source = user_turns[0].get("content") if user_turns else None
        question = user_turns[-1].get("content") if len(user_turns) > 1 else None
        self.server.record({
            "protocol": protocol, "model": MODEL if model == MODEL else "[redacted]",
            "roles": roles, "message_count": len(turns), "follow_up_count": max(0, len(user_turns) - 1),
            "context_valid": not errors, "errors": errors,
            "public_source": SOURCE if source == SOURCE else "[redacted]",
            "public_question": question if isinstance(question, str) and question in PUBLIC_QUESTIONS else ("[redacted]" if question else None),
        })
        if errors:
            self.reply(422, {"error": {"message": "Fixture rejected incomplete conversation context"}})
            return
        turn = len(user_turns) - 1
        text = answer_for_turn(turn)
        if protocol == "chat":
            payload = {"id": "fixture-chat", "object": "chat.completion", "model": MODEL,
                       "choices": [{"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}]}
        elif protocol == "responses":
            payload = {"id": "fixture-response", "object": "response", "model": MODEL, "status": "completed",
                       "output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": text}]}]}
        else:
            payload = {"id": "fixture-message", "type": "message", "role": "assistant", "model": MODEL,
                       "content": [{"type": "text", "text": text}], "stop_reason": "end_turn"}
        self.reply(200, payload)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--log", type=Path, default=Path("build/mock-requests.jsonl"))
    arguments = parser.parse_args()
    server = FixtureServer(("127.0.0.1", arguments.port), arguments.log)
    print(json.dumps({"ready": True, "base_url": f"http://localhost:{server.server_port}/v1",
                      "model": MODEL, "dummy_key": DUMMY_KEY, "log": str(arguments.log.resolve())}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
