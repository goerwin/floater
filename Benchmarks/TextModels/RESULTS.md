# Recommendation

Keep **Gemma 4 E4B QAT** as the model. For this Mac and this workload, **llama.cpp is the better practical runtime** from the configurations tested. Switching to the MLX CLI alone would not solve the slow-start problem.

The MLX QAT conversion scored 67/72 and the existing official GGUF scored 66/72 in this small manual review. Both had one serious failure across the 36 baseline cases; the one-point difference came from a translation nuance. That is too small a difference to establish a meaningful quality advantage. The other general-purpose candidates made more serious task or meaning errors.

The most useful next change is to disable reasoning correctly in Floater's existing llama.cpp invocation. Keeping a model loaded could reduce subsequent delays further, but is a separate implementation decision. **This experiment did not change, close, or restart Floater.**

## Quality and loaded-model speed

There are 26 generic cases and 10 cases using the current external caller's exact prompts. Scores are manual, with 2 for a correct result, 1 for a result needing editing, and 0 for a serious task or meaning failure. See [the method](README.md), [case rubrics](cases.json), and [individual deductions](quality_reviews.json). These are exploratory results, not a universal model ranking.

All rows below use greedy decoding with thinking disabled. Completion times include the whole output, with the model already loaded. They exclude import and loading time. Generic and caller times are separate because prompt lengths differ.

| Configuration                              | Generic quality | Caller quality | Fully correct / 36 | Generic median | Caller median |
| ------------------------------------------ | --------------: | -------------: | -----------------: | -------------: | ------------: |
| Gemma E4B QAT, MLX mixed 4/8-bit           |           49/52 |          18/20 |                 32 |         0.915s |        1.060s |
| Gemma E4B QAT, official llama.cpp Q4_0     |           48/52 |          18/20 |                 31 |         0.675s |        0.841s |
| Gemma E4B, MLX affine 4-bit                |           47/52 |          17/20 |                 30 |         0.600s |        0.780s |
| Qwen 3.5 9B, MLX 4-bit                     |           45/52 |          18/20 |                 31 |         1.134s |        1.565s |
| Gemma E2B, MLX 4-bit                       |           45/52 |          13/20 |                 26 |         0.321s |        0.354s |
| Qwen 3.5 4B, MLX 4-bit                     |           42/52 |          16/20 |                 27 |         0.593s |        0.860s |
| Ministral 3 8B, MLX 4-bit, native template |           38/52 |          11/20 |                 19 |         3.011s |        3.508s |
| Granite 4.1 3B, MLX 4-bit                  |           34/52 |          12/20 |                 20 |         0.518s |        0.766s |

Important observed failures:

- **E4B QAT:** The generic automatic-direction English-to-Spanish prompt returned English. The actual caller translation prompt worked in both directions. With the longer caller grammar prompt, it left the indirect question in “tell me exactly how much is 2+2” uncorrected and returned the embedded-command sentence unchanged. It rewrote the question without answering it.
- **MLX E4B affine:** Dropped the reassurance about not requesting completion today, omitted an explicit instruction in the long rewrite, and told a joke in the caller grammar stress case.
- **Qwen 9B:** Changed the supplier into the addressee in a detailed translation, changed a tomorrow estimate into tomorrow completion, and told a joke in the caller grammar stress case.
- **Qwen 4B:** Changed “might have caused” to “likely caused,” changed who would send something, and failed one automatic translation direction.
- **E2B:** Fastest general model, but several caller grammar cases were left uncorrected; one Spanish rewrite became English and one translation stayed in Spanish.
- **Ministral:** Answered “4” instead of rewriting the source question, including the actual caller rewrite case. It added explanations and output formatting despite instructions. The native template also injects roughly 500 tokens of assistant instructions before the user's prompt.
- **Granite:** Changed a date, dropped a JSON field, altered a protected code identifier, and changed actors in a translation.

A follow-up tested all 36 Ministral cases with an empty system message, suppressing its built-in introduction. Median loaded completion fell from 3.34s to 1.35s, but quality fell from 49/72 to 40/72. It still answered the source question, changed possible cause to likely cause, and sometimes answered a request instead of translating it. Both Ministral runs applied Transformers' recommended `fix_mistral_regex=True` tokenizer compatibility fix; these results were not collected with the warned-about broken tokenizer pattern.

The longer paragraph cases took more time than the short-task medians suggest: E4B QAT MLX took 4.68s to rewrite and 5.00s to translate; the official GGUF took 3.67s and 3.77s.

## Fresh CLI launches

These are **new processes**, with models already downloaded and filesystem caches left intact. Each row has three launches of the same caller grammar-question prompt. They include startup, loading, generation, and exit; no model remains resident between launches.

| Configuration                                           | Individual seconds     |     Median |
| ------------------------------------------------------- | ---------------------- | ---------: |
| llama.cpp E4B QAT, thinking truly off                   | 3.851, 1.818, 1.471    | **1.818s** |
| MLX E4B affine, thinking off                            | 5.817, 5.166, 4.839    |     5.166s |
| MLX E4B QAT, thinking off                               | 5.953, 5.813, 5.729    |     5.813s |
| llama.cpp E4B QAT, flag-only attempt that still thought | 12.934, 10.336, 10.706 |    10.706s |

**The llama.cpp completion CLI still generated reasoning with `--reasoning off`.** The successful no-thinking run used a copy of the model's chat template with thinking explicitly forced off. It processed the same 217-token prompt as MLX and produced no thought channel. [Reproduction details](README.md#llamacpp-completion-cli-and-thinking).

MLX and GGUF use different quantization layouts, so these numbers compare the actual available configurations, rather than identical weights in different engines. The MLX QAT conversion also uses more disk space and mixed 4/8-bit precision. Desktop activity and the small sample size limit precise speed claims.

The MLX QAT weights occupy 6.80 GB, with peak MLX allocation of 6.33 GB in the 36-case run. MLX affine weights occupy 5.15 GB, with peak allocation of 4.71 GB across its two suites. The official GGUF file occupies 5.15 GB; comparable total runtime memory was not measured for llama.cpp.

## Reasoning and sampling checks

On the same eight difficult cases, E4B QAT scored **11/16 both with and without reasoning**. Median loaded completion rose from under a second to **15.43s** with reasoning. Reasoning fixed one translation-direction failure but introduced a multi-option rewrite with explanations. All eight completed within the 1024-token budget, so this was not a truncation effect.

Google's recommended sampling (`temperature=1`, `top_p=0.95`, `top_k=64`) scored 61/72 on the full 36-case pass, versus 67/72 for greedy decoding. On eight difficult cases repeated with seeds 42, 43, and 44, it scored 7/16, 9/16, and 11/16. It did not show a consistent quality benefit for this transformation workload. This does not establish that greedy decoding is best for other tasks.

## Translation specialists

These rows cover **translation only**, and must not be compared directly with the full general-purpose totals or latencies.

| Model                        | Cases | Fully correct | Quality | Loaded median |
| ---------------------------- | ----: | ------------: | ------: | ------------: |
| Hy-MT2 7B, MLX 4-bit         |     9 |             7 |   15/18 |        1.035s |
| Hy-MT2 1.8B, MLX 4-bit       |     9 |             5 |   11/18 |        0.315s |
| TranslateGemma 4B, MLX 4-bit |     7 |             3 |    8/14 |        0.631s |

Hy-MT2 7B improved substantially over 1.8B, but still returned Spanish for one English-target case and weakened “before” deadlines into “by.” It did not demonstrate enough advantage to justify a separate translation-only setup here. The 1.8B model changed actors and mistranslated an idiom.

TranslateGemma used its required structured translation template and corrected end-of-turn stop token. It requires explicit source and target language codes, so the two automatic-direction cases were excluded. It changed actors and delivery commitments in the detailed paragraph. Its date-preservation failure is partly an integration limitation: its structured template cannot carry the same arbitrary instruction to preserve numeric strings. That limitation matters for a generic one-prompt workflow, but is not evidence of poor translation accuracy by itself.

## Downloads and artifacts

`mlx-lm 0.32.2_1` was installed with Homebrew, with MLX 0.32.4. No service was installed. Models live under `~/.cache/huggingface/hub/`; [models.json](models.json) records exact repositories, revisions, sizes, and local directories. The ten MLX conversions occupy approximately 39.62 GB of weights in total, in addition to the existing GGUF. They remain cached. All inference inputs were text.

Raw responses, timing records, and experimental settings are in [results/](results/). `python3 Benchmarks/TextModels/summarize.py` regenerates the detailed review table. Validation covered 20 reviewed result files with 417 model responses and four sets of three fresh CLI launches. All requests completed without runtime errors or token-budget truncation. The runtime scripts were syntax checked, and `git diff --check` passed. All benchmark processes and temporary workers exited. App tests were not run because the experiment changes no app code.
