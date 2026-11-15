#!/usr/bin/env python3
"""Measure a fresh installed CLI process, including imports, loading, and exit."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

from benchmark_cases import load_cases
from benchmark_lock import benchmark_lock


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--runtime", choices=["mlx", "llamacpp"], default="mlx")
    parser.add_argument("--output", required=True)
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--chat-template-file", help="llama.cpp template override, used to force thinking off")
    args = parser.parse_args()
    prompt = next(case["prompt"] for case in load_cases("caller") if case["id"] == "caller_grammar_question")
    if args.runtime == "mlx":
        command = [
            "/opt/homebrew/bin/mlx_lm.generate", "--model", args.model,
            "--prompt", prompt, "--temp", "0", "--seed", "42", "--max-tokens", "512",
            "--chat-template-config", '{"enable_thinking":false}', "--verbose", "false",
        ]
    else:
        command = [
            "/opt/homebrew/bin/llama-completion", "--model", args.model,
            "--prompt", prompt, "--temp", "0", "--seed", "42", "--predict", "512",
            "--ctx-size", "8192", "--offline", "--no-display-prompt", "--simple-io", "--color", "off", "--no-escape",
            "--conversation", "--single-turn", "--jinja", "--reasoning", "off",
            "--log-colors", "off",
        ]
        if args.chat_template_file:
            command += ["--chat-template-file", args.chat_template_file]
    environment = {**os.environ, "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "TOKENIZERS_PARALLELISM": "false"}
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w") as handle:
        for repeat in range(args.repeat):
            start = time.perf_counter()
            result = subprocess.run(["/usr/bin/nice", "-n", "10", *command], env=environment, capture_output=True, text=True, timeout=90)
            record = {
                "name": args.name, "runtime": args.runtime, "model": args.model,
                "case": "caller_grammar_question", "repeat": repeat,
                "seconds": time.perf_counter() - start, "exit_code": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr,
                "chat_template_file": args.chat_template_file,
                "has_reasoning": "<|channel>thought" in result.stdout or "<think>" in result.stdout,
            }
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
            handle.flush()
            print(json.dumps({key: value for key, value in record.items() if key not in ["stdout", "stderr"]}), flush=True)


if __name__ == "__main__":
    with benchmark_lock():
        main()
