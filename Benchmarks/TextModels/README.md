# Local text model comparison

Tested on November 14, 2026, on an Apple M3 Pro with 18 GiB unified memory and 11 CPU cores. Software versions are recorded in [environment.json](environment.json).

This directory contains standalone CLI experiments. It does not change Floater's model provider, prompts, or running app. No persistent service is installed or started.

## Test method

- [cases.json](cases.json): 26 generic cases covering English and Spanish grammar, rewriting, translation, numbers, uncertainty, actors, Markdown, JSON, and code identifiers.
- [caller_cases.json](caller_cases.json): 10 cases using the existing external caller's actual templates, snapshotted in [caller_prompts.json](caller_prompts.json). These include additional instructions and automatic translation direction. Caller templates are benchmark inputs only.
- Each request starts with a fresh conversation. The model stays loaded between requests, but no prompt KV cache is carried between them.
- Baseline: temperature 0, seed 42, thinking disabled, maximum 512 generated tokens. Models use their own supplied chat templates. No model-specific prompt tuning was applied to the general models.
- Ministral's tokenizer uses Transformers' recommended `fix_mistral_regex=True` compatibility fix. A separate `--empty-system` experiment suppresses its built-in assistant introduction; it is not mixed into the native-template baseline.
- Runs are sequential and use `nice +10`. MLX benchmarks limit allocation to 8 GiB, wired memory to 6 GiB, and cache to 256 MiB. CLI startup tests use the installed CLI's own memory defaults.
- Loaded-model completion includes prompt processing and the entire output. First-answer latency measures the first nonempty final-answer text. Neither includes loading or Python imports.
- Fresh CLI tests include process startup, imports, model loading, generation, and exit. The disk cache is already populated; these are not uncached disk or first-download measurements.
- Memory figures are peak MLX allocations, not total process RSS or system memory. Disk weights include components that text-only inference may not load. GB is decimal; GiB is binary.

The llama.cpp loaded-model harness briefly starts a localhost-only worker, then terminates it. It never becomes a background service. MLX uses the Python API directly. Harnesses share a lock to avoid overlapping inference.

## Quality review

Every baseline answer was manually reviewed against its case rubric. [quality_reviews.json](quality_reviews.json) records deductions and reasons. All other cases within an explicitly reviewed result file scored 2.

- **2:** Faithful, correct, and follows the task requirements.
- **1:** Usable, but needs an edit for an omission, awkward expression, or incomplete correction.
- **0:** Wrong task or language, or an important actor, fact, certainty, or instruction changes.

This is a small, deliberately difficult English/Spanish test set, with one greedy output per case. It is not a universal model ranking or an estimate of real-world error rates. Several prompts were added after observing earlier failures, so this is an exploratory comparison rather than a held-out evaluation. Normal paraphrases, contractions, and formal Spanish *usted* are accepted.

Translation specialists are evaluated separately. Hy-MT2 receives only translation cases. TranslateGemma requires a structured source/target language template, so it receives seven fixed-direction cases, without the two automatic-direction cases. Its template cannot carry the same arbitrary formatting instructions; the date-preservation failure is therefore an integration limitation as well as an unsuitable result for this use case. Do not compare their totals or median latencies directly with the full general-purpose suite.

## Reproduce

Install the runtime with Homebrew:

```sh
brew install mlx-lm
```

Models are downloaded from Hugging Face into `~/.cache/huggingface/hub/`, outside the repository. Exact snapshot revisions and local paths are recorded in each result file. Use a fully downloaded local snapshot for offline testing:

```sh
MODEL=/absolute/path/to/cached/snapshot
/opt/homebrew/opt/mlx-lm/libexec/bin/python Benchmarks/TextModels/benchmark_mlx.py \
  --model "$MODEL" --name candidate --suite all \
  --output /tmp/candidate.jsonl
```

Google's recommended Gemma sampling can be tested with `--temperature 1 --top-p 0.95 --top-k 64`. Use `--repeat 3` to test seeds 42, 43, and 44. `--thinking --max-tokens 1024` enables a separate reasoning experiment. These settings are recorded in result metadata; keep experiments separate from the baseline.

For a real fresh CLI process:

```sh
mlx_lm.generate --model "$MODEL" \
  --prompt 'Correct the grammar. Return only the corrected text: she go to school.' \
  --chat-template-config '{"enable_thinking":false}' \
  --temp 0 --max-tokens 512 --verbose false
```

`benchmark_cli.py` measures three fresh launches using the caller grammar-question case. `benchmark_llamacpp.py` measures the loaded GGUF baseline. Run either with `--help` for arguments. `python3 Benchmarks/TextModels/summarize.py` regenerates the baseline quality/timing table from the reviewed records.

GPU access is required for MLX even during import; an execution sandbox that hides Metal must allow GPU access for these commands.

### llama.cpp completion CLI and thinking

In Homebrew llama.cpp build b12359, `llama-completion --reasoning off` still produced thought-channel tokens in this experiment. The completion path does not pass the configured template kwargs into its initial `common_chat_templates_apply` call. The localhost server benchmark does pass `enable_thinking: false`, and its outputs contain no reasoning.

For the fair fresh-process comparison, the supplied Gemma QAT template was copied into a temporary benchmark file, with `{%- set enable_thinking = false -%}` prepended. The completion CLI then used `--chat-template-file` to load that copy. It processed the same 217-token caller prompt as MLX and stopped generating reasoning. This changes runtime formatting only; it does not edit the user's prompt or Floater.

`cli-llamacpp-e4b-thinking.jsonl` preserves the flag-only run, which still thought. `cli-llamacpp-e4b.jsonl` is the corrected no-thinking run. The observed flag-only delay must not be attributed to the runtime alone.

The copies can be regenerated from the cached MLX QAT snapshot:

```sh
python3 - "$MODEL/chat_template.jinja" /tmp/gemma-no-thinking.jinja <<'PY'
from pathlib import Path
import sys
Path(sys.argv[2]).write_text('{%- set enable_thinking = false -%}\n' + Path(sys.argv[1]).read_text())
PY

python3 Benchmarks/TextModels/benchmark_cli.py \
  --runtime llamacpp --model /absolute/path/to/gemma-4-E4B_q4_0-it.gguf \
  --name gemma-e4b-qat-no-thinking \
  --chat-template-file /tmp/gemma-no-thinking.jinja \
  --output /tmp/cli-llamacpp.jsonl
```

MLX affine 4-bit, MLX QAT mixed 4/8-bit, and Google's GGUF QAT Q4_0 are different weight conversions. The runtime comparisons describe these practical configurations; they do not isolate the speed or numerical accuracy of two engines running identical weights. Timings were collected while the desktop remained available for normal use and are based on small samples.
