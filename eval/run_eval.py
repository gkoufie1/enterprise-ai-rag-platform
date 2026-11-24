"""Run the evaluation set against the deployed API and score it.

Usage:
    RAG_TOKEN=... RAG_API_URL=https://.../query python eval/run_eval.py [eval/questions.jsonl]

Scores per question:
  retrieval  - the expected document is among the retrieved sources
  citation   - the answer cites the expected document
  keywords   - every expected keyword appears in the answer (case-insensitive)
  no_answer  - for questions the documents cannot answer: no citations in the reply
  blocked    - for unsafe input: the guardrail blocked it

Each run calls Claude once per answerable question (about 2 cents each with the defaults).
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def ask(url: str, token: str, question: str) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps({"question": question}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=35) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        return {"error": f"HTTP {exc.code}: {exc.read().decode(errors='replace')[:200]}"}


def score(case: dict, reply: dict) -> dict:
    if "error" in reply:
        return {"pass": False, "detail": reply["error"]}

    expect = case.get("expect", "answer")
    cited = {c["document_key"] for c in reply.get("citations", [])}
    if expect == "blocked":
        return {"pass": bool(reply.get("blocked")), "detail": "blocked" if reply.get("blocked") else "not blocked"}
    if expect == "no_answer":
        return {"pass": not cited, "detail": "abstained" if not cited else f"cited {sorted(cited)}"}

    answer = reply.get("answer", "").lower()
    checks = {
        "retrieval": case["expected_source"] in {s["document_key"] for s in reply.get("sources", [])},
        "citation": case["expected_source"] in cited,
        "keywords": all(k.lower() in answer for k in case.get("expected_keywords", [])),
    }
    failed = [name for name, ok in checks.items() if not ok]
    return {"pass": not failed, "detail": "ok" if not failed else "failed: " + ", ".join(failed), **checks}


def main() -> int:
    url = os.environ.get("RAG_API_URL")
    token = os.environ.get("RAG_TOKEN")
    if not url or not token:
        print("Set RAG_API_URL (the query_api_url output) and RAG_TOKEN (scripts/get_token.sh).", file=sys.stderr)
        return 2

    path = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).with_name("questions.jsonl"))
    cases = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]

    results = []
    for case in cases:
        started = time.time()
        reply = ask(url, token, case["question"])
        result = {"id": case["id"], "seconds": round(time.time() - started, 1), **score(case, reply)}
        results.append(result)
        print(f"{'PASS' if result['pass'] else 'FAIL'}  {case['id']:<30} {result['seconds']:>5}s  {result['detail']}")
        time.sleep(0.3)  # stay under the API throttle

    answerable = [r for r in results if "retrieval" in r]
    passed = sum(r["pass"] for r in results)
    print()
    print(f"Overall: {passed}/{len(results)} passed")
    if answerable:
        for metric in ("retrieval", "citation", "keywords"):
            hits = sum(r[metric] for r in answerable)
            print(f"  {metric:<10} {hits}/{len(answerable)} ({hits / len(answerable):.0%})")

    Path(__file__).with_name("results.json").write_text(json.dumps(results, indent=2))
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
