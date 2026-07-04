# LLM Wiki 회사 환경 셋업 가이드 (AI 실행용)

> 이 문서는 **셋업을 수행하는 AI(Claude Code 등)가 읽고 실행**하는 것을 전제로 작성되었다.
> 환경이 원본(개인 macOS)과 다를 수 있으므로, 각 단계의 "의도"를 이해하고 환경에 맞게 적응할 것.
> 사용자에게 물어봐야 할 결정 사항은 ❓로 표시했다.

## 0. 배경 — 왜 이 구조인가

원본 사용자는 v1에서 "모든 활동을 다 저장"하는 wiki를 운영했고, 194개 문서 중
다시 읽힌 것은 상위 20~30개뿐인 write-only 창고가 되었다. v2는 그 교훈으로 만들어졌다.
**이 셋업의 목표는 지식을 많이 쌓는 것이 아니라, 답변에 다시 인용되는 wiki를 만드는 것이다.**

핵심 설계 3가지 — 어떤 환경이든 이것만은 유지할 것:

1. **좁은 도메인 게이트**: 수집 도메인을 2~3개로 한정하고 vault CLAUDE.md에 명문화.
   ingest AI가 이 파일을 읽고 스킵을 판단하므로, CLAUDE.md가 곧 필터다.
2. **2단계 분리**: 세션 로그는 전량 로컬 버퍼(session-logs/, git 제외)에 쌓고,
   wiki 승격은 하루 1회 배치 ingest가 기준에 따라 선별한다. 세션 중 판단하지 않는다.
3. **읽기 경로**: SessionStart에 wiki/index.md를 주입해 모든 세션이 기존 지식 위에서 시작한다.
   index가 비대해지면 토큰 비용이 세션마다 발생하므로 "제목 한 줄" 형태를 유지한다.

## 1. 아키텍처

```
[Claude Code 세션]
  ├─ SessionStart hook ─→ wiki/index.md 를 컨텍스트로 주입 (+ git pull)
  ├─ UserPromptSubmit/PostToolUse/Stop/SessionEnd hook ─→ session-logs/*.md 기록 (로컬 전용)
  └─ SessionEnd hook ─→ wiki/ 변경분 auto commit/push (.gitignore 게이트 통과 시만)

[스케줄러: launchd(macOS) 또는 cron/systemd(Linux)]
  ├─ 매일 07:00  auto-ingest.sh  → claude -p 로 미처리 로그를 wiki 로 선별 승격
  ├─ 매일 07:20  auto-lint.sh    → wiki 정합성 검사 (선택)
  └─ 매일 07:40  session-log-retention.sh → ingested 후 30일 지난 로그 삭제
```

실행 주체: hook 스크립트(session-logger.mjs, wiki-context-injector.mjs)와
배치 스크립트(auto-ingest.sh, auto-lint.sh)는 **gieok** 프로젝트가 제공한다.
retention 스크립트만 이 패키지(vault-skeleton/scripts/)에 포함되어 있다.

## 2. 사전 요구사항

- Claude Code CLI 설치 + 인증 완료 (`claude -p "hi"` 가 동작해야 함)
  - ❓ 회사가 Bedrock/Vertex 게이트웨이를 쓰는 경우 해당 인증이 headless(cron) 환경에서도
    유효한지 확인. cron 은 쉘 rc 파일을 읽지 않으므로 API 키·PATH를 스케줄러 설정에 명시해야 한다.
- node (hook 스크립트 실행용), git
- **gieok 저장소**: `github.com/gaebalai/gieok` (v0.6.0 기준).
  - ❓ 회사망에서 GitHub 접근이 안 되면 개인 머신에서 tarball로 반입할 것.
  - gieok 자체 인스톨러(`scripts/install-hooks.sh`, `install-schedule.sh`, `install-cron.sh`,
    `install-launchagents.sh`)가 있으므로 가능하면 그것을 사용하고, 아래 snippets/는
    인스톨러를 못 쓰는 환경의 수동 셋업용 참고로 삼을 것.

## 3. 셋업 절차

### 3-1. 도메인 결정 (가장 중요 — 코드보다 먼저)

❓ 사용자에게 물어볼 것: **"3개월 뒤 다시 검색할 회사 업무 주제 2~3개"**.
예: `camera-driver`, `isp-tuning`, `build-infra` 등. 많을수록 실패한다 — 3개 초과는 거절하고
"일단 2개로 시작, 필요가 증명되면 추가" 를 권할 것.

### 3-2. vault 생성

1. ❓ vault 위치·이름을 정한다 (회사 git 저장소로 관리할 디렉토리).
2. `vault-skeleton/` 내용을 통째로 복사한다.
3. `CLAUDE.md` 와 `schema.md` 의 `{{DOMAIN_1}}`, `{{DOMAIN_2}}` 플레이스홀더를
   3-1에서 정한 도메인 slug 로 치환하고, 각 도메인의 한 줄 설명을 채운다.
4. git init 후 **원격은 반드시 사내 git 서버로만** 설정한다. 외부(github.com 등) 원격 금지.
5. `.gitignore` 에 `session-logs/` 가 있는지 확인 — auto commit hook 과 ingest 의
   안전 게이트가 이 항목의 존재를 검사한다. 없으면 git 작업을 전부 스킵한다 (의도된 동작).

### 3-3. hooks 설치

`~/.claude/settings.json` 의 `hooks` 에 gieok hook 을 등록한다.
`snippets/hooks-settings.json` 이 원본 구성 그대로이며, `{{VAULT_PATH}}` 와
`{{GIEOK_PATH}}` 를 실제 절대경로로 치환해 병합할 것 (기존 hooks 를 덮어쓰지 말고 병합).

주의사항:
- hook 설정은 **세션 시작 시점에 고정**된다. 설치 후 열려 있던 세션은 반영되지 않는다.
- session-logs 에는 대화 전문이 남는다. 비밀정보가 포함될 수 있으므로
  session-logs/ 는 어떤 경우에도 커밋되면 안 된다 (gieok 의 `scan-secrets.sh` 참고).

### 3-4. 스케줄링 (환경 분기)

| 환경 | 방법 |
|---|---|
| macOS | `snippets/launchd/*.plist` 를 `~/Library/LaunchAgents/` 에 복사, 경로 치환 후 `launchctl load`. gieok `install-launchagents.sh` 로도 가능 |
| Linux 서버 | `snippets/cron/gieok-crontab.example` 참고해 crontab 등록. gieok `install-cron.sh` 로도 가능 |

공통 함정 (환경 불문 확인할 것):
- cron/launchd 는 로그인 쉘이 아니다 → `claude`, `node`, `git` 의 PATH 를 명시해야 한다.
  원본 plist 는 `EnvironmentVariables > PATH` 에 volta/mise/homebrew 경로를 나열했다.
- 시간대: ingest 는 업무 시작 전(예: 07:00)이 적절. 서버 TZ 확인.
- macOS 는 잠자기 시 미실행 작업을 catchup 하지만 cron 은 안 한다 →
  상시 가동 서버라면 무관, 개인 워크스테이션이면 anacron 또는 systemd timer(Persistent=true) 고려.

### 3-5. 보존 정책 (retention)

`vault-skeleton/scripts/session-log-retention.sh` 를 vault 에 포함시켰다.
매일 ingest **이후** 시각에 스케줄 등록: `session-log-retention.sh <vault-path> 30`
- `ingested: true` + mtime 30일 경과 로그만 삭제. 미처리 로그는 절대 삭제하지 않는다.
- 처음 실행 전 `GIEOK_RETENTION_DRY_RUN=1` 로 대상을 확인할 것.

## 4. 회사 환경 특수 수칙 (개인 환경과 다른 부분)

1. **sensitivity 기본값을 `internal` 로** 한다 (개인 환경은 public 이 다수였음).
   `confidential` 문서는 git commit 자체를 금지 — `.gitignore` 의
   `wiki/**/*-confidential.md` 패턴을 활용하고, vault CLAUDE.md 에도 명시되어 있다.
2. push 대상은 사내 git 서버만. auto commit hook 의 `git push` 가 외부로 나가지 않는지
   원격 URL 을 반드시 확인한다.
3. 고객사·프로젝트 코드네임, 미공개 스펙 수치는 wiki 에 그대로 쓰지 말고
   개념·패턴 수준으로 sanitize 해서 기록하도록 CLAUDE.md 수집 기준에 포함되어 있다.
4. ingest 가 쓰는 모델/계정이 회사 정책에 맞는지 확인 (`claude -p` 는 로그인된 계정의
   기본 모델을 사용한다).

## 5. 검증 체크리스트 (셋업 완료 판정)

- [ ] 새 Claude Code 세션을 열면 응답 컨텍스트에 wiki index 가 주입된다
- [ ] 세션에서 도구를 몇 번 사용한 뒤 `<vault>/session-logs/` 에 로그 md 가 생긴다
- [ ] `GIEOK_DRY_RUN=1 bash <gieok>/scripts/auto-ingest.sh` 가 에러 없이 미처리 건수를 보고한다
- [ ] 실제 ingest 1회 후: 도메인 밖 잡담 로그는 스킵되고 `ingested: true` 마킹만 된다
- [ ] `wiki/log.md` 에 ingest 기록이 남고, git log 에 auto commit 이 생긴다
- [ ] `GIEOK_RETENTION_DRY_RUN=1` retention 실행이 정상 보고한다
- [ ] `session-logs/` 가 `git status` 에 나타나지 않는다 (gitignore 확인)

## 6. 운영하며 지킬 것 (셋업 AI가 사용자에게 전달할 것)

- **index.md 는 제목 한 줄 목록을 유지** — 수백 줄로 비대해지면 매 세션 토큰 비용이 그대로 증가
- 도메인 추가 유혹을 경계 — "이것도 저장하면 좋지 않을까" 는 v1 을 창고로 만든 사고방식.
  추가는 같은 주제가 반복적으로 아쉬웠을 때만
- 분기별로 한 번 `wiki/log.md` 의 스킵/승격 비율을 보고 기준을 조정
- wiki 의 성공 지표는 문서 수가 아니라 **답변에 인용되는 빈도**
