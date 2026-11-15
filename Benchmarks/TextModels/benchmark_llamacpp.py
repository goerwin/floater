#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import socket
import subprocess
import time
import urllib.request
from benchmark_cases import load_cases
from benchmark_lock import benchmark_lock


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--suite", choices=["base", "caller", "all"], default="base")
    parser.add_argument("--case", action="append")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    cases = load_cases(args.suite)
    if args.case:
        cases = [case for case in cases if case["id"] in args.case]
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    base_url = f"http://127.0.0.1:{port}"
    with output.with_suffix(".stderr.log").open("w") as log:
        start = time.perf_counter()
        process = subprocess.Popen([
            "/usr/bin/nice", "-n", "10", "/opt/homebrew/bin/llama-server",
            "--model", args.model, "--host", "127.0.0.1", "--port", str(port),
            "--ctx-size", "8192", "--parallel", "1", "--offline", "--no-mmproj",
            "--reasoning", "off", "--log-verbosity", "1", "--log-colors", "off",
        ], stdout=log, stderr=log)
        try:
            while True:
                if process.poll() is not None:
                    raise RuntimeError("llama.cpp exited during startup; see stderr log")
                if time.perf_counter() - start > 90:
                    raise TimeoutError("llama.cpp did not become ready")
                try:
                    with urllib.request.urlopen(base_url + "/health", timeout=1) as response:
                        if response.status == 200:
                            break
                except Exception:
                    time.sleep(0.2)
            metadata = {"event": "loaded", "name": "llamacpp-e4b-no-thinking", "model": args.model, "load_seconds": time.perf_counter() - start, "temperature": 0.0, "seed": 42, "thinking": False}
            print(json.dumps(metadata), flush=True)
            with output.open("w") as handle:
                handle.write(json.dumps(metadata) + "\n")
                for case in cases:
                    body = json.dumps({
                        "messages": [{"role": "user", "content": case["prompt"]}],
                        "temperature": 0, "seed": 42, "max_tokens": 512,
                        "cache_prompt": False, "stream": True,
                        "chat_template_kwargs": {"enable_thinking": False},
                    }).encode()
                    request = urllib.request.Request(base_url + "/v1/chat/completions", data=body, headers={"Content-Type": "application/json"})
                    start = time.perf_counter()
                    answer = ""
                    reasoning = ""
                    first_answer = None
                    finish_reason = None
                    with urllib.request.urlopen(request, timeout=90) as response:
                        for line in response:
                            if not line.startswith(b"data: ") or line.strip() == b"data: [DONE]":
                                continue
                            data = json.loads(line[6:])
                            if "error" in data:
                                raise RuntimeError(data["error"])
                            for choice in data.get("choices", []):
                                delta = choice.get("delta", {})
                                answer += delta.get("content") or ""
                                reasoning += delta.get("reasoning_content") or ""
                                if first_answer is None and answer.strip():
                                    first_answer = time.perf_counter() - start
                                finish_reason = choice.get("finish_reason") or finish_reason
                    record = {"event": "result", "name": metadata["name"], "case": case["id"], "category": case["category"], "answer": answer, "reasoning": reasoning, "seconds": time.perf_counter() - start, "first_answer_seconds": first_answer, "finish_reason": finish_reason}
                    handle.write(json.dumps(record, ensure_ascii=False) + "\n")
                    handle.flush()
                    print(json.dumps({key: value for key, value in record.items() if key not in ["answer", "reasoning"]}), flush=True)
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    with benchmark_lock():
        main()
