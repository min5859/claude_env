# opus-orchestration 셋업 가이드

Claude Code에 **모델 계층 오케스트레이션**을 붙이는 패키지. 메인 세션 + 서브에이전트(Opus/Sonnet/Haiku)를
역할별로 나누고, PreToolUse 훅으로 유도하며, `off/hard/soft` 세 모드를 심링크 토글로 전환한다.

> 이 문서는 사람이 읽어도, 셋업을 대행하는 AI가 읽고 실행해도 되게 작성했다. 환경(특히 셸·OS)이 다르면
> "의도"를 이해하고 맞게 적응할 것. 사용자 결정 사항은 ❓로 표시.

## 1. 세 가지 모드

| 모드 | 메인 | 주 위임 | 게이트 | 언제 |
|---|---|---|---|---|
| **off** | (강제 없음) | — | 통과 | 비활성 (기본값) |
| **hard** | Opus | implementer(Sonnet) 실행자 · runner(Haiku) 잡무 | 메인 직접수정 **차단**(한 턴 코드 2파일 초과·Bash 인플레이스) | 품질 우선. 강모델이 직접 손대는 범위를 통제 |
| **soft** | Sonnet | deep-reasoner(Opus) 조력자 · runner(Haiku) 잡무 | 차단 없이 **넛지**(위임 권고) | 비용 우선. 싼 메인이 대부분 실행, 어려운 것만 Opus로 상향 |

hard = 하향 위임(비싼 메인을 아래로 흘림), soft = 상향 에스컬레이션(싼 메인이 위로 올림). Haiku runner는 공통.

## 2. 패키지 구성

```
opus-orchestration/
├── install.sh / uninstall.sh   # 멱등 설치·제거 (백업 포함)
├── SETUP-GUIDE.md              # 이 문서
├── bin/opus-orchestration      # 토글 스크립트 (off|hard|soft|status)
├── mode-hard.md / mode-soft.md / empty.md   # 모드별 메인 지침(active.md 심링크 대상)
├── env.sh                      # 상태에 따라 메인 모델·계층 alias 고정
├── hooks/orchestration-gate.py # PreToolUse 게이트 (모드 분기: hard=차단, soft=넛지)
└── agents/
    ├── implementer.md   (model: sonnet)  # hard 실행자
    ├── deep-reasoner.md (model: opus)    # soft 조력자
    └── runner.md        (model: haiku)   # 공통 잡무
```

설치되면 ~/.claude 에 다음이 생긴다: `~/.claude/opus-orchestration/`(위 파일 사본 + `active.md` 심링크 +
`state/`), `~/.claude/agents/{implementer,deep-reasoner,runner}.md`(→ 위 심링크),
`~/.local/bin/opus-orchestration`, `~/.claude/.opus-orchestration-state`(모드 값).

## 3. 사전 요구사항

- Claude Code CLI + 인증 완료.
- **python3** (게이트 훅 + settings.json 병합). `python3 --version` 확인.
- `~/.local/bin` 이 PATH 에 있을 것. 없으면 rc 에 `export PATH="$HOME/.local/bin:$PATH"` 추가.
- 셸: zsh 또는 bash. ⚠️ 로그인 zsh 는 `.bashrc` 를 안 읽는다 — install 은 `$SHELL` 과 존재하는 rc 를 보고
  맞는 파일에 넣는다. 토글 스크립트는 macOS 기본 bash 3.2 호환(`${x^^}` 같은 bash4 문법 미사용).
- **Claude Code 버전**: 게이트의 서브에이전트 식별(`agent_id`)·턴 카운팅(`prompt_id`)은 CC v2.1.196+ 의 PreToolUse
  payload 필드에 의존한다(문서 확인됨). 더 낮은 버전은 `prompt_id` 부재 시 transcript 기반 fallback 으로 동작하며
  (정밀도만 낮아지고 깨지지 않음), soft 모드는 넛지뿐이라 영향이 미미하다.

## 4. 설치 (회사 PC)

```bash
bash opus-orchestration/install.sh
```

install.sh 가 하는 일 (전부 멱등·비파괴, 수정 대상은 1회 백업):
1. 설정 파일을 `~/.claude/opus-orchestration/` 로 복사.
2. 토글 스크립트를 `~/.local/bin/` 에 설치.
3. `~/.claude/agents/` 에 에이전트 3종 심링크.
4. 상태값 초기화 — **기존 설치가 있으면 현재 모드(hard/soft) 유지**, 없으면 `off`. (재설치가 켜둔 모드를 끄지 않는다.)
5. `~/.claude/settings.json` 의 `hooks.PreToolUse` 에 게이트 항목 **병합**(기존 훅 보존).
6. `~/.claude/CLAUDE.md` 끝에 `@~/.claude/opus-orchestration/active.md` 추가.
7. 셸 rc 에 `source ~/.claude/opus-orchestration/env.sh` 추가.

❓ 이 저장소의 루트 `CLAUDE.md`/`settings.json` 을 회사 PC 글로벌로 따로 배포한다면, install 은 그와 별개로
**라이브 `~/.claude/` 를 수정**한다. 배포 순서(먼저 글로벌 배포 → 그 다음 install)를 지키면 import/훅이 최종본에 남는다.

### 구버전(mode 개념 없던 on/off 하드블록판)에서 업그레이드
- install 이 자동 처리: 구 잔재 `opus.md` 삭제, 새 파일(mode-hard/soft, implementer, 모드분기 gate/env) 설치,
  기존 훅/CLAUDE.md/rc 라인 중복 없이 유지.
- ⚠️ **레거시 상태값 `on` 은 자동 매핑하지 않는다**(hard였는지 soft였는지 문자열로 알 수 없음). install 은 `off`로 두고
  안내를 출력한다. 구 `on`(하드블록·Opus 메인)과 동등하게 쓰려면 설치 후 **`opus-orchestration hard`** 를 명시 실행.
- 실행 중이던 세션은 새 게이트를 다음 툴 호출부터 읽지만, 모델·env 완전 반영은 새 세션·새 셸부터.

## 5. 사용법

```bash
opus-orchestration status     # 현재 모드 + active.md 대상
opus-orchestration hard       # Opus 메인 + 하드블록
opus-orchestration soft       # Sonnet 메인 + 소프트 넛지
opus-orchestration off        # 비활성
```

적용 타이밍(중요):
- **게이트·모델은 다음 Claude Code 세션부터** 반영(훅·모델은 세션 시작 시 로드).
- **env.sh 는 새 셸부터**(셸 시작 시 1회 source). 즉시 반영은 `source ~/.zshrc`.
- 메인 모델이 자동으로 안 바뀌면 세션에서 `/model opus`(hard)·`/model sonnet`(soft) 로 지정
  (`/model`·`--model` 이 env 보다 우선).

튜닝(선택): `OPUS_ORCH_HARD_LIMIT`(기본 2), `OPUS_ORCH_NUDGE_THRESHOLD`(기본 3) 환경변수.

## 6. 검증 체크리스트

- [ ] `opus-orchestration hard` → status 가 `hard`, active.md → `mode-hard.md`
- [ ] `opus-orchestration soft` → status 가 `soft`, active.md → `mode-soft.md`
- [ ] `opus-orchestration off` → status 가 `off`, active.md → `empty.md`
- [ ] `~/.claude/agents/{implementer,deep-reasoner,runner}.md` 심링크가 실제 파일로 해석됨
- [ ] `python3 -m json.tool ~/.claude/settings.json` 통과(유효 JSON), 기존 훅 보존
- [ ] hard 모드에서 새 세션이 메인=Opus, soft 에서 메인=Sonnet (또는 `/model` 로 확인)
- [ ] 게이트 단위 테스트(선택): 아래 명령이 hard 에서 3번째 .py 편집을 exit 2 로 막는지
  ```bash
  H=~/.claude/opus-orchestration/hooks/orchestration-gate.py
  opus-orchestration hard
  for i in 1 2 3; do echo "{\"session_id\":\"t\",\"prompt_id\":\"p\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/f$i.py\"}}" | python3 "$H"; echo "exit=$?"; done
  opus-orchestration off
  ```

## 7. 제거

```bash
bash opus-orchestration/uninstall.sh
```
install 이 추가한 것만 수술적으로 되돌린다. 백업(`*.bak-orchestration`)은 남긴다.

## 8. 동작 원리 (한 줄씩)

- **모드 값** `~/.claude/.opus-orchestration-state`(off/hard/soft)를 훅·env.sh·토글이 각각 읽어 분기.
- **게이트**는 메인 에이전트만 대상(서브에이전트는 `agent_id`/`agent_type`로 식별해 통과), 예외는 fail-open. Bash 검사는 따옴표·heredoc 인지 토큰화로 문자열 데이터 오탐을 막는다.
- **넛지**(soft)는 차단 대신 `additionalContext` 만 주입(한 턴 1회). `permissionDecision` 은 설정하지 않는다 — `"allow"` 는 권한 프롬프트를 우회하는 부작용이 있다.
- **토글**은 상태파일과 `active.md` 심링크 대상만 바꿔 기존 설정을 건드리지 않는다.
