#!/usr/bin/env bash
# opus-orchestration 제거 — install.sh 가 추가한 것만 되돌린다(수술적). 백업 파일은 남겨둔다.
set -uo pipefail

CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/opus-orchestration"
BIN_DIR="$HOME/.local/bin"

echo "[1] 토글 off (활성 상태면 먼저 내림)"
[ -x "$BIN_DIR/opus-orchestration" ] && "$BIN_DIR/opus-orchestration" off >/dev/null 2>&1 || true

echo "[2] agents 심링크 제거"
for a in implementer deep-reasoner runner; do
    link="$CLAUDE_DIR/agents/$a.md"
    if [ -L "$link" ] && readlink "$link" | grep -q 'opus-orchestration/agents/'; then rm -f "$link"; echo "  rm $link"; fi
done

echo "[3] 설정 디렉토리·토글·상태파일 제거"
rm -rf "$DEST"; echo "  rm -rf $DEST"
rm -f "$BIN_DIR/opus-orchestration"; echo "  rm $BIN_DIR/opus-orchestration"
rm -f "$CLAUDE_DIR/.opus-orchestration-state"

echo "[4] settings.json 에서 게이트 항목 제거"
python3 - "$HOME" <<'PY'
import json, os, sys
home = sys.argv[1]
p = os.path.join(home, ".claude", "settings.json")
try:
    with open(p, encoding="utf-8") as f: cfg = json.load(f)
except Exception:
    sys.exit(0)
pre = cfg.get("hooks", {}).get("PreToolUse", [])
new = [e for e in pre if not (isinstance(e, dict) and any(
    "orchestration-gate.py" in (h.get("command", "")) for h in e.get("hooks", [])))]
if len(new) != len(pre):
    cfg["hooks"]["PreToolUse"] = new
    with open(p, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False); f.write("\n")
    print("  settings.json: 게이트 제거")
else:
    print("  settings.json: 게이트 없음 (skip)")
PY

echo "[5] CLAUDE.md / 셸 rc 에서 추가 라인 제거"
python3 - "$HOME" <<'PY'
import os, sys
home = sys.argv[1]
def strip(path, needles):
    try:
        with open(path, encoding="utf-8") as f: lines = f.readlines()
    except Exception:
        return
    out = [ln for ln in lines if not any(n in ln for n in needles)]
    if out != lines:
        with open(path, "w", encoding="utf-8") as f: f.writelines(out)
        print("  cleaned:", path)
strip(os.path.join(home, ".claude", "CLAUDE.md"), ["@~/.claude/opus-orchestration/active.md"])
for rc in (".zshrc", ".bashrc"):
    strip(os.path.join(home, rc),
          ["opus-orchestration/env.sh", "# opus-orchestration: 모드별 모델 계층"])
PY

echo
echo "✅ 제거 완료. 백업(*.bak-orchestration)은 보존했습니다. 새 셸/CC 세션부터 반영됩니다."
