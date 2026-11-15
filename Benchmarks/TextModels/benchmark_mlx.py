#!/usr/bin/env python3
import time

PROCESS_START = time.perf_counter()

import argparse
import gc
import json
import os
from pathlib import Path
import signal
import statistics
import sys

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import mlx.core as mx
from benchmark_cases import load_cases
from benchmark_lock import benchmark_lock
from mlx_lm import load, stream_generate
from mlx_lm.sample_utils import make_sampler

IMPORT_SECONDS = time.perf_counter() - PROCESS_START
ROOT = Path(__file__).resolve().parent


def final_text(text):
    for opening, closing in [("<think>", "</think>"), ("<|channel>thought\n", "<channel|>")]:
        if opening.startswith(text):
            return ""
        if text.startswith(opening):
            if closing not in text:
                return ""
            return text.split(closing, 1)[1].lstrip("\n")
    return text


def timed_out(_signum, _frame):
    raise TimeoutError("Request exceeded 90 seconds")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="Local cached snapshot directory")
    parser.add_argument("--name", required=True)
    parser.add_argument("--suite", choices=["base", "caller", "all"], default="base")
    parser.add_argument("--output", required=True)
    parser.add_argument("--category", action="append")
    parser.add_argument("--case", action="append")
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--top-p", type=float, default=1.0)
    parser.add_argument("--top-k", type=int, default=0)
    parser.add_argument("--min-p", type=float, default=0.0)
    parser.add_argument("--thinking", action="store_true")
    parser.add_argument("--empty-system", action="store_true", help="Suppress a model template's built-in assistant instructions")
    args = parser.parse_args()
    os.nice(10)
    mx.set_memory_limit(8 * 1024**3)
    mx.set_wired_limit(6 * 1024**3)
    mx.set_cache_limit(256 * 1024**2)
    signal.signal(signal.SIGALRM, timed_out)

    cases = load_cases(args.suite)
    if args.category:
        cases = [case for case in cases if case["category"] in args.category]
    if args.case:
        cases = [case for case in cases if case["id"] in args.case]
    if args.name == "translategemma":
        cases = [case for case in cases if not case["id"].startswith("translate_infer_")]
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    config = json.loads((Path(args.model) / "config.json").read_text())
    tokenizer_config = {"fix_mistral_regex": True} if config.get("model_type") == "mistral3" else {}
    model, tokenizer = load(args.model, tokenizer_config=tokenizer_config)
    if args.name == "translategemma":
        tokenizer.add_eos_token("<end_of_turn>")
    mx.synchronize()
    load_seconds = time.perf_counter() - started
    metadata = {
        "event": "loaded", "name": args.name, "model": args.model,
        "import_seconds": IMPORT_SECONDS, "load_seconds": load_seconds,
        "active_memory_gb": mx.get_active_memory() / 1e9,
        "temperature": args.temperature, "seed": args.seed,
        "max_tokens": args.max_tokens, "top_p": args.top_p,
        "top_k": args.top_k, "min_p": args.min_p,
        "thinking": args.thinking,
        "empty_system": args.empty_system,
        "suite": args.suite,
        "tokenizer_config": tokenizer_config,
    }
    print(json.dumps(metadata), flush=True)
    records = []
    with output.open("w") as handle:
        handle.write(json.dumps(metadata) + "\n")
        for repeat in range(args.repeat):
            for case in cases:
                mx.clear_cache()
                mx.reset_peak_memory()
                mx.random.seed(args.seed + repeat)
                raw = ""
                first_token_seconds = None
                first_answer_seconds = None
                last = None
                start = time.perf_counter()
                record = {"event": "result", "name": args.name, "case": case["id"], "category": case["category"], "repeat": repeat}
                try:
                    content = case["prompt"]
                    if args.name == "translategemma":
                        source = "es" if case["id"] in ["translate_es_en", "translate_false_friends", "translate_paragraph"] else "en"
                        content = [{"type": "text", "source_lang_code": source, "target_lang_code": "en" if source == "es" else "es", "text": case["prompt"].split("\n\n", 1)[1]}]
                    messages = [{"role": "user", "content": content}]
                    if args.empty_system:
                        messages.insert(0, {"role": "system", "content": ""})
                    prompt = tokenizer.apply_chat_template(
                        messages,
                        tokenize=False, add_generation_prompt=True,
                        enable_thinking=args.thinking,
                    )
                    signal.alarm(90)
                    sampler = make_sampler(temp=args.temperature, top_p=args.top_p, top_k=args.top_k, min_p=args.min_p)
                    for response in stream_generate(model, tokenizer, prompt, max_tokens=args.max_tokens, sampler=sampler):
                        last = response
                        raw += response.text
                        elapsed = time.perf_counter() - start
                        if first_token_seconds is None and response.text:
                            first_token_seconds = elapsed
                        if first_answer_seconds is None and final_text(raw).strip():
                            first_answer_seconds = elapsed
                    mx.synchronize()
                    record.update({
                        "answer": final_text(raw), "raw": raw,
                        "seconds": time.perf_counter() - start,
                        "first_token_seconds": first_token_seconds,
                        "first_answer_seconds": first_answer_seconds,
                        "prompt_tokens": last.prompt_tokens if last else 0,
                        "generation_tokens": last.generation_tokens if last else 0,
                        "generation_tps": last.generation_tps if last else 0,
                        "finish_reason": last.finish_reason if last else None,
                        "peak_memory_gb": mx.get_peak_memory() / 1e9,
                    })
                except Exception as error:
                    record.update({"error": repr(error), "raw": raw, "seconds": time.perf_counter() - start})
                finally:
                    signal.alarm(0)
                records.append(record)
                handle.write(json.dumps(record, ensure_ascii=False) + "\n")
                handle.flush()
                print(json.dumps({key: value for key, value in record.items() if key not in ["raw", "answer"]}), flush=True)
                if "error" in record:
                    gc.collect()
                    mx.clear_cache()

    successful = [record for record in records if "error" not in record]
    if successful:
        print(json.dumps({
            "event": "summary", "name": args.name, "cases": len(successful),
            "median_seconds": statistics.median(record["seconds"] for record in successful),
            "median_first_answer_seconds": statistics.median(record["first_answer_seconds"] for record in successful if record["first_answer_seconds"] is not None),
        }), flush=True)


if __name__ == "__main__":
    with benchmark_lock():
        main()
