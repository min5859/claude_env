#!/usr/bin/env python3
"""opus-orchestration PreToolUse gate — 모드 분기(off/hard/soft).

메인 에이전트만 대상으로 한다. 서브에이전트(agent_id/agent_type)와 off 모드는 통과. 예외는 fail-open.
  - hard: 메인의 직접 코드수정을 차단(한 턴 distinct 코드 파일 HARD_MAX 초과 시 exit 2, Bash 인플레이스도 차단).
  - soft: 차단하지 않고 조언만 주입(임계 SOFT_THRESHOLD 도달 시 additionalContext, 권한 흐름 불개입, 한 턴 1회).
env:
  OPUS_ORCH_HARD_LIMIT       hard 모드 허용 직접 코드파일 수 (기본 2 → 3번째부터 차단)
  OPUS_ORCH_NUDGE_THRESHOLD  soft 모드 넛지 임계 distinct 코드파일 수 (기본 3)
"""
import json
import os
import re
import shlex
import sys
import time

HOME = os.path.expanduser("~")
STATE_FLAG = os.path.join(HOME, ".claude", ".opus-orchestration-state")
STATE_DIR = os.path.join(HOME, ".claude", "opus-orchestration", "state")


def _envint(name, default):
    try:
        return max(1, int(os.environ.get(name, str(default))))
    except Exception:
        return default


HARD_MAX = _envint("OPUS_ORCH_HARD_LIMIT", 2)
SOFT_THRESHOLD = _envint("OPUS_ORCH_NUDGE_THRESHOLD", 3)

# 비코드 확장자 = 대상 제외. 확장자 없는 파일도 비코드 취급(오탐 방지).
NON_CODE_EXT = {
    ".md", ".markdown", ".mdx", ".rst", ".txt", ".text",
    ".json", ".jsonl", ".ndjson", ".yaml", ".yml", ".toml", ".ini",
    ".cfg", ".conf", ".env", ".properties",
    ".csv", ".tsv", ".xml", ".lock", ".log",
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".pdf", ".ico",
}


def is_code_file(path):
    if not path:
        return False
    ext = os.path.splitext(str(path))[1].lower()
    if not ext:
        return False
    return ext not in NON_CODE_EXT


def get_mode():
    try:
        with open(STATE_FLAG, "r", encoding="utf-8") as f:
            v = f.read().strip().lower()
    except Exception:
        return "off"
    if v in ("hard", "soft"):
        return v
    if v == "on":  # 레거시 호환
        return "soft"
    return "off"


def is_subagent(payload):
    return bool(payload.get("agent_id") or payload.get("agent_type"))


def get_turn_id(payload):
    for k in ("prompt_id", "promptId", "prompt_uuid"):
        v = payload.get(k)
        if v:
            return "p:" + str(v)
    tp = payload.get("transcript_path")
    if tp:
        try:
            last = None
            with open(os.path.expanduser(tp), "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    if obj.get("type") == "user":
                        last = obj.get("uuid") or last
            if last:
                return "t:" + str(last)
        except Exception:
            pass
    return "s:" + str(payload.get("session_id", ""))


def edited_path(tool_name, tool_input):
    if tool_name in ("Write", "Edit", "MultiEdit"):
        return tool_input.get("file_path")
    if tool_name == "NotebookEdit":
        return tool_input.get("notebook_path") or tool_input.get("file_path")
    return None


# Bash 인플레이스/덮어쓰기 감지 — 따옴표 안 문자열과 heredoc 본문은 데이터로 취급해 오탐을 막는다.
_REDIR_TOKENS = {">", ">>", ">|", "&>", "&>>"}
_SED_INPLACE = re.compile(r"-[EnrsuzbW]*i")
_PERL_INPLACE = re.compile(r"-[a-z0-9]*i(?![A-Za-z])")


def _strip_heredocs(cmd):
    # heredoc 본문 제거 — 본문 속 'sed -i' 같은 텍스트가 명령으로 오인되는 것 방지. 여는 줄은 유지.
    lines = cmd.split("\n")
    out, delim = [], None
    for ln in lines:
        if delim is not None:
            if ln.strip() == delim:
                delim = None
            continue
        m = re.search(r"<<-?\s*(['\"]?)([A-Za-z_]\w*)\1", ln)
        if m:
            delim = m.group(2)
        out.append(ln)
    return "\n".join(out)


def _segments(cmd):
    # 따옴표 인지 토큰화 후 ; | & 기준으로 파이프라인 세그먼트 분리. 토큰화 실패는 fail-open(None).
    lex = shlex.shlex(_strip_heredocs(cmd), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    try:
        tokens = list(lex)
    except ValueError:
        return None
    segs, cur = [], []
    for t in tokens:
        if t and not set(t) - set(";|&"):
            segs.append(cur)
            cur = []
        else:
            cur.append(t)
    segs.append(cur)
    return segs


def bash_direct_write_reason(cmd):
    segs = _segments(cmd or "")
    if not segs:
        return None
    for seg in segs:
        for i, t in enumerate(seg):
            rest = seg[i + 1:]
            name = os.path.basename(t)
            if name in ("sed", "gsed") and any(
                x == "--in-place" or x.startswith("--in-place=") or _SED_INPLACE.match(x)
                for x in rest
            ):
                return "sed 인플레이스 편집"
            if name == "perl" and any(_PERL_INPLACE.match(x) for x in rest):
                return "perl 인플레이스 편집"
            if name == "tee":
                for x in rest:
                    if not set(x) - set("<>|&;"):  # 리다이렉트·연산자부터는 tee 대상 아님
                        break
                    if x.startswith("-"):
                        continue
                    if is_code_file(x):
                        return "tee로 코드 파일 쓰기"
            if t in _REDIR_TOKENS and rest and is_code_file(rest[0]):
                return "리다이렉션으로 코드 파일 쓰기"
            if name in ("sh", "bash", "zsh", "dash", "ksh") and "-c" in rest:
                inner = rest[rest.index("-c") + 1:]
                if inner:
                    r = bash_direct_write_reason(inner[0])
                    if r:
                        return r
    return None


def load_state(session_id):
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", str(session_id)) or "unknown"
    path = os.path.join(STATE_DIR, safe + ".json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict):
                return path, data
    except Exception:
        pass
    return path, {"turn_id": None, "files": [], "nudged": False}


STATE_TTL = 7 * 24 * 3600  # 세션 상태 파일 보존 기간(초)


def _prune_stale_state(now):
    # 세션마다 하나씩 쌓이는 state/*.json 무한 누적 방지. 실패는 무시(fail-open).
    try:
        for e in os.scandir(STATE_DIR):
            if e.name.endswith(".json") and now - e.stat().st_mtime > STATE_TTL:
                os.unlink(e.path)
    except Exception:
        pass


def save_state(path, data):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        _prune_stale_state(time.time())
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
    except Exception:
        pass


def block(reason):
    sys.stderr.write(reason)
    sys.exit(2)


def nudge(message):
    # permissionDecision 은 설정하지 않는다 — "allow" 는 권한 프롬프트를 우회하는 부작용이 있다.
    # additionalContext 만 주입하면 권한 흐름은 평소대로 진행된다.
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": message,
        }
    }
    sys.stdout.write(json.dumps(out, ensure_ascii=False))
    sys.exit(0)


def handle_hard(tool_name, tool_input, state_path, state):
    if tool_name == "Bash":
        reason = bash_direct_write_reason(tool_input.get("command") or "")
        if reason:
            block(
                "[opus-orchestration/hard] 메인의 Bash 직접 코드 수정 차단 (" + reason + ").\n"
                "편집 도구(Edit/Write)를 쓰거나 implementer(Sonnet)에 위임하라."
            )
        sys.exit(0)

    path = edited_path(tool_name, tool_input)
    if not is_code_file(path):
        sys.exit(0)

    files = state.get("files") or []
    if path in files:
        sys.exit(0)
    if len(files) >= HARD_MAX:
        block(
            "[opus-orchestration/hard] 메인은 한 턴에 코드 파일 " + str(HARD_MAX)
            + "개까지만 직접 수정할 수 있다 (요청: " + str(path) + ").\n"
            "이후 코드 작업은 implementer(Sonnet)에 위임하라."
        )
    files.append(path)
    state["files"] = files
    save_state(state_path, state)
    sys.exit(0)


def handle_soft(tool_name, tool_input, state_path, state):
    already = bool(state.get("nudged"))

    if tool_name == "Bash":
        reason = bash_direct_write_reason(tool_input.get("command") or "")
        if reason and not already:
            state["nudged"] = True
            save_state(state_path, state)
            nudge(
                "[opus-orchestration/soft] Bash 직접 코드 수정 감지 (" + reason + "). "
                "편집 도구(Edit/Write)가 리뷰·추적에 유리하다. 원인 파악이나 설계가 얽힌 변경이면 "
                "deep-reasoner(Opus)에 위임을 고려하라. (강제 아님)"
            )
        save_state(state_path, state)
        sys.exit(0)

    path = edited_path(tool_name, tool_input)
    if not is_code_file(path):
        save_state(state_path, state)
        sys.exit(0)

    files = state.get("files") or []
    if path not in files:
        files.append(path)
    state["files"] = files
    if (not already) and len(files) >= SOFT_THRESHOLD:
        state["nudged"] = True
        save_state(state_path, state)
        nudge(
            "[opus-orchestration/soft] 이번 턴에 코드 파일 " + str(len(files)) + "개를 직접 편집 중이다. "
            "교차 변경이거나 설계 복잡도가 있으면 deep-reasoner(Opus)에 설계·검토를, 조사·로그 확인은 "
            "runner(Haiku)에 위임하는 것을 고려하라. 단순 반복 편집이면 그대로 진행해도 된다. (강제 아님)"
        )
    save_state(state_path, state)
    sys.exit(0)


def main():
    mode = get_mode()
    if mode == "off":
        sys.exit(0)

    raw = sys.stdin.read()
    payload = json.loads(raw) if raw.strip() else {}
    if is_subagent(payload):
        sys.exit(0)

    tool_name = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}
    if isinstance(tool_input, str):
        try:
            tool_input = json.loads(tool_input)
        except Exception:
            tool_input = {}

    turn_id = get_turn_id(payload)
    state_path, state = load_state(payload.get("session_id"))
    if state.get("turn_id") != turn_id:
        state = {"turn_id": turn_id, "files": [], "nudged": False}

    if mode == "hard":
        handle_hard(tool_name, tool_input, state_path, state)
    else:
        handle_soft(tool_name, tool_input, state_path, state)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)
