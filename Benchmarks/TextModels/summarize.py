#!/usr/bin/env python3
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parent


def main():
    reviews = json.loads((ROOT / "quality_reviews.json").read_text())["reviews"]
    print("| Result | Suite | Cases | Fully correct | Score | Median completion | Median first answer | Peak MLX GB |")
    print("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
    for filename, review in reviews.items():
        records = [json.loads(line) for line in (ROOT / "results" / filename).read_text().splitlines()]
        records = [record for record in records if record.get("event") == "result"]
        assert not any("error" in record for record in records), filename
        assert len({(record["case"], record.get("repeat", 0)) for record in records}) == len(records), filename
        known = {key for record in records for key in [record["case"], f"{record['case']}@{record.get('repeat', 0)}"]}
        unknown = set(review["exceptions"]) - known
        assert not unknown, (filename, unknown)
        for suite in ["base", "caller"]:
            selected = [record for record in records if record["case"].startswith("caller_") == (suite == "caller")]
            if not selected:
                continue
            scores = [review["exceptions"].get(f"{record['case']}@{record.get('repeat', 0)}", review["exceptions"].get(record["case"], [2]))[0] for record in selected]
            first = [record["first_answer_seconds"] for record in selected if record.get("first_answer_seconds") is not None]
            peak = max((record.get("peak_memory_gb", 0) for record in selected), default=0)
            memory = f"{peak:.2f}" if peak else "n/a"
            print(f"| {filename.removesuffix('.jsonl')} | {suite} | {len(selected)} | {scores.count(2)} | {sum(scores)}/{len(scores)*2} | {statistics.median(record['seconds'] for record in selected):.3f}s | {statistics.median(first):.3f}s | {memory} |")


if __name__ == "__main__":
    main()
