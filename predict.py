#!/usr/bin/env python
"""Generate SWE-bench predictions via litellm (openrouter) for given instance ids.

Writes a JSONL file with {"instance_id", "model_patch", "model_name_or_path"}.
Already-generated instances are skipped on re-run (resumable).
"""
import argparse
import json
import os
import re
import sys

from datasets import load_dataset

SYSTEM_PROMPT = (
    "You are an expert software engineer tasked with fixing a bug. "
    "Respond with ONLY a unified diff (git patch) that fixes the issue. "
    "Wrap the patch in a ```diff code block. Do not include any other explanation."
)

DIFF_RE = re.compile(r"```(?:diff)?\s*\n(.*?)```", re.DOTALL)


def extract_patch(text: str) -> str:
    m = DIFF_RE.search(text or "")
    return m.group(1).strip() if m else ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--instance_ids", nargs="*", default=None,
                    help="subset of instance ids (default: all)")
    ap.add_argument("--out", required=True, help="output JSONL path")
    ap.add_argument("--model", required=True, help="litellm model id")
    ap.add_argument("--max_tokens", type=int, default=8192)
    args = ap.parse_args()

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    done = set()
    try:
        with open(args.out) as f:
            for line in f:
                done.add(json.loads(line)["instance_id"])
    except FileNotFoundError:
        pass

    ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
    if args.instance_ids:
        wanted = set(args.instance_ids)
        ds = ds.filter(lambda x: x["instance_id"] in wanted)

    import litellm

    with open(args.out, "a") as out:
        for ex in ds:
            iid = ex["instance_id"]
            if iid in done:
                continue
            print(f"[predict] {iid}", flush=True)
            prompt = (
                f"Repo: {ex['repo']}\n"
                f"Issue:\n{ex['problem_statement']}\n\n"
                "Provide the unified diff patch that fixes this issue."
            )
            patch = ""
            try:
                # OpenRouter models need the "openrouter/" provider prefix
                # for litellm to know which API to call. litellm rejects bare
                # model ids like "stealth/ox-alpha" with BadRequestError.
                litellm_model = (
                    args.model
                    if "/" in args.model.split("/")[0] or args.model.startswith(("openai/", "anthropic/", "azure/"))
                    else f"openrouter/{args.model}"
                )
                resp = litellm.completion(
                    model=litellm_model,
                    messages=[
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": prompt},
                    ],
                    temperature=0.0,
                    max_tokens=args.max_tokens,
                )
                msg = resp.choices[0].message
                patch = extract_patch(msg.content or "")
                if not patch and getattr(msg, "reasoning_content", None):
                    # reasoning-only reply: try to pull a diff out of the reasoning text
                    patch = extract_patch(msg.reasoning_content)
            except Exception as e:  # noqa: BLE001 — keep going on API errors
                print(f"[predict] ERROR {iid}: {e}", file=sys.stderr, flush=True)
            out.write(json.dumps({
                "instance_id": iid,
                "model_patch": patch,
                "model_name_or_path": args.model,
            }) + "\n")
            out.flush()


if __name__ == "__main__":
    main()
