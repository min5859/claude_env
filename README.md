# claude_env

Claude Code 개인 환경을 코드로 관리해 여러 PC(개인·회사)에 이식·공유하기 위한 저장소.

## 루트 파일 (글로벌 설정 마스터)

- `CLAUDE.md` — 글로벌 지침 마스터 (배포 시 `~/.claude/CLAUDE.md`).
- `settings.json` — 글로벌 설정 마스터 (배포 시 `~/.claude/settings.json`).
- `statusline.sh` — 상태줄 스크립트.

## 패키지

각 패키지는 자체 셋업 가이드를 포함한다. 회사 PC 등 새 환경에서 해당 가이드를 따라 적용한다.

| 패키지 | 내용 | 가이드 |
|---|---|---|
| `llm_wiki2/` | 재조회율 중심 개인 지식 wiki(도메인 게이트 + 배치 ingest + 읽기 경로) 셋업 키트 | `llm_wiki2/SETUP-GUIDE.md` |
| `opus-orchestration/` | 모델 계층 오케스트레이션(off/hard/soft 토글, PreToolUse 게이트, 서브에이전트 Opus/Sonnet/Haiku) | `opus-orchestration/SETUP-GUIDE.md` |

### opus-orchestration 빠른 설치

```bash
bash opus-orchestration/install.sh   # 멱등·비파괴, 초기 off
opus-orchestration status            # hard | soft | off 전환
```

## 주의

- 회사 PC 적용 시 push 원격이 사내 정책에 맞는지 확인(민감정보 유출 방지).
- 설정 변경은 다음 Claude Code 세션·새 셸부터 반영된다(훅·env는 시작 시 로드).
