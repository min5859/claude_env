#!/usr/bin/env bash
# opus-orchestration 설치 — 이 패키지의 설정을 ~/.claude 에 이식한다.
# 멱등(재실행 안전) · 수정 대상은 1회 백업(*.bak-orchestration) · 기존 설정 비파괴(병합).
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # 이 스크립트가 있는 opus-orchestration/
CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/opus-orchestration"
BIN_DIR="$HOME/.local/bin"
STATE_FLAG="$CLAUDE_DIR/.opus-orchestration-state"

command -v python3 >/dev/null 2>&1 || { echo "❌ python3 가 필요합니다 (게이트 훅 + settings.json 병합)"; exit 1; }

backup() { # $1 = file, 원본 1회 백업(이미 있으면 유지)
    if [ -f "$1" ] && [ ! -f "$1.bak-orchestration" ]; then
        cp -p "$1" "$1.bak-orchestration"; echo "  backup: $1.bak-orchestration"
    fi
    return 0
}

echo "[1/7] 설정 파일 복사 → $DEST"
mkdir -p "$DEST/hooks" "$DEST/agents" "$DEST/state" "$CLAUDE_DIR/agents" "$BIN_DIR"
cp "$PKG/mode-hard.md" "$PKG/mode-soft.md" "$PKG/empty.md" "$PKG/env.sh" "$DEST/"
cp "$PKG/hooks/orchestration-gate.py" "$DEST/hooks/"
cp "$PKG/agents/implementer.md" "$PKG/agents/deep-reasoner.md" "$PKG/agents/runner.md" "$DEST/agents/"
chmod +x "$DEST/hooks/orchestration-gate.py"
rm -f "$DEST/opus.md"   # 구버전(mode 이전) 잔재 정리

echo "[2/7] 토글 스크립트 → $BIN_DIR/opus-orchestration"
cp "$PKG/bin/opus-orchestration" "$BIN_DIR/opus-orchestration"
chmod +x "$BIN_DIR/opus-orchestration"

echo "[3/7] ~/.claude/agents 심링크"
for a in implementer deep-reasoner runner; do
    ln -sfn "../opus-orchestration/agents/$a.md" "$CLAUDE_DIR/agents/$a.md"
done

echo "[4/7] 상태값 (기존 설치면 현재 모드 유지, 없으면 off)"
CUR="off"; TGT="empty.md"; LEGACY_ON=0
if [ -r "$STATE_FLAG" ]; then
    case "$(cat "$STATE_FLAG" 2>/dev/null)" in
        hard) CUR="hard"; TGT="mode-hard.md" ;;
        soft) CUR="soft"; TGT="mode-soft.md" ;;
        on)   CUR="off";  TGT="empty.md"; LEGACY_ON=1 ;;   # 구버전 'on' 은 hard/soft 판별 불가 → 자동 매핑 안 함
        *)    CUR="off";  TGT="empty.md" ;;
    esac
fi
printf '%s' "$CUR" > "$STATE_FLAG"
ln -sfn "$TGT" "$DEST/active.md"
echo "  모드: $CUR (active.md -> $TGT)"
if [ "$LEGACY_ON" = 1 ]; then
    echo "  ⚠️  구버전 'on' 상태 감지 — 신버전은 off/hard/soft 로 나뉩니다."
    echo "      구버전 on(하드블록·Opus 메인)과 동등하려면 설치 후: opus-orchestration hard"
fi

echo "[5/7] settings.json 에 PreToolUse 게이트 병합"
backup "$CLAUDE_DIR/settings.json"
python3 - "$HOME" <<'PY'
import json, os, sys
home = sys.argv[1]
p = os.path.join(home, ".claude", "settings.json")
if os.path.exists(p):
    try:
        with open(p, encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception as e:
        print("  ❌ settings.json 파싱 실패 — 기존 파일 보호를 위해 병합을 중단합니다: %s" % e)
        print("     파일을 고친 뒤 install.sh 를 다시 실행하세요.")
        sys.exit(1)
else:
    cfg = {}
hooks = cfg.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])
cmd = 'python3 "%s"' % os.path.join(home, ".claude", "opus-orchestration", "hooks", "orchestration-gate.py")
matcher = "Write|Edit|NotebookEdit|MultiEdit|Bash"
exists = any(
    any("orchestration-gate.py" in (h.get("command", "")) for h in e.get("hooks", []))
    for e in pre if isinstance(e, dict)
)
if exists:
    print("  settings.json: 게이트 이미 등록됨 (skip)")
else:
    pre.append({"matcher": matcher, "hooks": [{"type": "command", "command": cmd}]})
    with open(p, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False); f.write("\n")
    print("  settings.json: PreToolUse 게이트 추가")
PY

echo "[6/7] CLAUDE.md import 라인"
CM="$CLAUDE_DIR/CLAUDE.md"
backup "$CM"
if ! grep -qF '@~/.claude/opus-orchestration/active.md' "$CM" 2>/dev/null; then
    printf '\n@~/.claude/opus-orchestration/active.md\n' >> "$CM"; echo "  import 추가"
else
    echo "  import 이미 존재 (skip)"
fi

echo "[7/7] 셸 rc 에 env.sh source"
add_rc() { # $1 = rc file (없으면 생성)
    local rc="$1"; [ -z "$rc" ] && return 0
    backup "$rc"
    if grep -qF 'opus-orchestration/env.sh' "$rc" 2>/dev/null; then return 0; fi
    printf '\n# opus-orchestration: 모드별 모델 계층 고정(상태 hard/soft 일 때만)\nsource ~/.claude/opus-orchestration/env.sh\n' >> "$rc"
    echo "  rc updated: $rc"
}
case "${SHELL:-}" in
    *zsh)  add_rc "$HOME/.zshrc" ;;
    *bash) add_rc "$HOME/.bashrc" ;;
esac
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do [ -f "$rc" ] && add_rc "$rc"; done

case ":${PATH}:" in
    *":$BIN_DIR:"*) : ;;
    *) echo "  ⚠️  $BIN_DIR 가 PATH 에 없습니다 — rc 에 'export PATH=\"\$HOME/.local/bin:\$PATH\"' 추가 필요";;
esac

echo
echo "✅ 설치 완료. 현재 모드: $CUR."
echo "   • 게이트·모델은 다음 Claude Code 세션부터, env.sh 는 새 셸(또는 source ~/.zshrc·~/.bashrc)부터 반영됩니다."
echo "   • 사용: opus-orchestration {hard|soft|off|status}"
