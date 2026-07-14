# opus-orchestration env.sh
# 상태(off/hard/soft)에 따라 모델 계층을 고정한다.
#   hard — 메인=Opus(오케스트레이터), implementer 서브=Sonnet(frontmatter), runner=Haiku.
#   soft — 메인=Sonnet, deep-reasoner 서브=Opus(frontmatter), runner=Haiku.
#   off  — 어떤 모델도 강제하지 않는다.
# 서브에이전트 계층은 각 agents/*.md frontmatter가 담당하고, 여기서는 메인 모델과 alias pin만 export.
#
# 주의:
#   - 이 파일은 셸 시작 시 1회 source 된다. 모드 전환 후에는 새 셸(또는 재-source)부터 반영된다.
#   - ANTHROPIC_MODEL은 세션 내 /model 선택이나 `claude --model ...` 플래그가 있으면 그쪽이 우선한다.
#   - 모델 세대가 바뀌면(예: Claude 5 계열 출시) 아래 핀을 수동으로 재점검한다 — 세대 자동 추종을 막는 것이 이 핀의 목적이다.

__opus_orch_state_file="${HOME}/.claude/.opus-orchestration-state"
__opus_orch_mode="off"
if [ -r "${__opus_orch_state_file}" ]; then
    __opus_orch_mode="$(cat "${__opus_orch_state_file}" 2>/dev/null)"
fi
[ "${__opus_orch_mode}" = "on" ] && __opus_orch_mode="soft"   # 레거시 호환

# 계층 alias pin (세대 바뀜 방지) — 모드 공통
if [ "${__opus_orch_mode}" = "hard" ] || [ "${__opus_orch_mode}" = "soft" ]; then
    export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-8"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-5"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001"
fi

case "${__opus_orch_mode}" in
    hard) export ANTHROPIC_MODEL="claude-opus-4-8" ;;    # 메인 = Opus
    soft) export ANTHROPIC_MODEL="claude-sonnet-5" ;;    # 메인 = Sonnet
    *)    : ;;                                            # off = 강제 없음
esac

unset __opus_orch_state_file __opus_orch_mode
