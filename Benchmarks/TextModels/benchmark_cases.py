import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load_cases(suite):
    cases = json.loads((ROOT / "cases.json").read_text()) if suite in ["base", "all"] else []
    if suite in ["caller", "all"]:
        templates = json.loads((ROOT / "caller_prompts.json").read_text())
        for case in json.loads((ROOT / "caller_cases.json").read_text()):
            prompt = templates[case["category"]]
            if case["category"] != "rewrite":
                prompt = templates["shared"] + "\n\nTASK\n" + prompt
            if case.get("additional"):
                prompt += "\n\nADDITIONAL INSTRUCTIONS\n" + case["additional"]
            cases.append({**case, "prompt": prompt + "\n\n" + case["source"]})
    return cases
