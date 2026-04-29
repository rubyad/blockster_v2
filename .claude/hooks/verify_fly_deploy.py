#!/usr/bin/env python3
"""
PreToolUse Bash hook — enforces CLAUDE.md HARD RULE that every `flyctl deploy`
must run from inside the target app's directory (the cwd, NOT the --app flag,
determines which Dockerfile is used).

Reads the Bash tool's input JSON on stdin. Outputs JSON on stdout to:
  - block deploys with no fly.toml in cwd,
  - block chained `cd … && flyctl deploy` (the hook subprocess sees parent
    cwd, not post-cd cwd, so it can't honestly verify the destination),
  - block `--config /tmp/other.toml` (bypasses cwd check),
  - emit a `DEPLOY VERIFIED: app=<name> dir=<pwd>` systemMessage on success.

Detection uses `shlex.split` instead of plain regex so quoted text inside
echo/git-commit messages can't false-trigger. shlex tokenizes shell input
the way bash would: `echo "cd && flyctl deploy"` becomes two tokens
(`echo`, `cd && flyctl deploy`) — the inner `&&` doesn't split because it's
inside a quoted string.
"""
import sys
import json
import os
import re
import shlex

CHAINED_REASON = (
    "DEPLOY BLOCKED: chained command (cd && deploy, ; deploy, etc) defeats "
    "the cwd check — the hook subprocess sees the parent cwd, not the post-cd "
    "cwd. Run cd as a separate Bash call FIRST so the persistent shell cwd is "
    "set, THEN run flyctl deploy as a standalone command in the next call."
)
CONFIG_REASON = (
    "DEPLOY BLOCKED: --config flag bypasses the cwd fly.toml check. Per "
    "CLAUDE.md hard rule, cd to the target app directory and run flyctl "
    "deploy without --config."
)
NO_FLYTOML_TEMPLATE = (
    "DEPLOY BLOCKED: no fly.toml in {cwd}. Per CLAUDE.md hard rule, cd to "
    "the target app dir before flyctl deploy. blockster-v2 = repo root, "
    "blockster-settler = contracts/blockster-settler/, high-rollers-elixir = "
    "high-rollers-elixir/."
)

SHELL_SEPARATORS = {"&&", "||", ";", "|"}


def emit_deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def emit_verified(app, cwd):
    msg = f"DEPLOY VERIFIED: app={app} dir={cwd}"
    print(json.dumps({
        "systemMessage": msg,
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": msg,
        }
    }))
    sys.exit(0)


def find_deploy_positions(tokens):
    """Returns (first_is_deploy, has_chained_deploy).

    Walks the token list and, for each "command position" — index 0 plus any
    index immediately after a shell separator token — checks if the next two
    non-env-var tokens are (`flyctl`|`fly`, `deploy`).
    """
    first_is_deploy = False
    has_chained_deploy = False
    i = 0
    n = len(tokens)
    while i < n:
        # Skip leading env-var assignments at this command position.
        j = i
        while j < n and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[j]):
            j += 1
        # Check if this command position starts with `flyctl deploy` or `fly deploy`.
        if j + 1 < n and tokens[j] in ("flyctl", "fly") and tokens[j + 1] == "deploy":
            if i == 0:
                first_is_deploy = True
            else:
                has_chained_deploy = True
        # Advance to the next command position — find the next separator.
        while i < n and tokens[i] not in SHELL_SEPARATORS:
            i += 1
        # Skip past the separator itself.
        i += 1
    return first_is_deploy, has_chained_deploy


def main():
    payload = json.load(sys.stdin)
    cmd = payload.get("tool_input", {}).get("command", "")

    try:
        tokens = shlex.split(cmd, posix=True)
    except ValueError:
        # Malformed shell (unclosed quote etc.) — let it through; bash will
        # fail it on its own, no point blocking unrelated commands.
        sys.exit(0)

    first_is_deploy, has_chained_deploy = find_deploy_positions(tokens)

    if not (first_is_deploy or has_chained_deploy):
        sys.exit(0)

    if has_chained_deploy and not first_is_deploy:
        emit_deny(CHAINED_REASON)

    # First-position deploy from here on. Check for --config bypass in the
    # token stream before the first separator. Tokens already strip quotes.
    for tok in tokens:
        if tok in SHELL_SEPARATORS:
            break
        if tok == "--config" or tok.startswith("--config="):
            emit_deny(CONFIG_REASON)

    cwd = os.getcwd()
    if not os.path.isfile("fly.toml"):
        emit_deny(NO_FLYTOML_TEMPLATE.format(cwd=cwd))

    app = "unknown"
    with open("fly.toml") as f:
        for line in f:
            m = re.match(r"""app\s*=\s*["']?([^"'\s]+)""", line)
            if m:
                app = m.group(1)
                break

    emit_verified(app, cwd)


if __name__ == "__main__":
    main()
