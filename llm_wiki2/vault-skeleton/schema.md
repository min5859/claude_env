# Wiki Schema — 운영 규칙

## Frontmatter 필수 필드

```yaml
---
title: "문서 제목"
domain: "{{DOMAIN_1}} | {{DOMAIN_2}}"          # 지식 도메인 (둘 밖이면 수집하지 않음)
sensitivity: "internal | confidential"          # 회사 환경 기본값 internal
tags: ["태그1", "태그2"]
created: "YYYY-MM-DD"
updated: "YYYY-MM-DD"
sources:
  - "raw-sources/파일명"                        # sensitivity 검토 후 배치한 원본
confidence: "high | medium | low"
related:
  - "wiki/관련문서.md"
---
```

### domain 기준

| 값 | 기준 |
|---|---|
| `{{DOMAIN_1}}` | {{DOMAIN_1_설명}} |
| `{{DOMAIN_2}}` | {{DOMAIN_2_설명}} |

두 값 밖의 주제는 wiki에 수집하지 않는다 (CLAUDE.md 수집 기준 참조).

### sensitivity 기준 (회사 환경)

| 값 | 기준 | git commit |
|---|---|---|
| `internal` | 사내 수준, 코드네임·미공개 수치 없음 | 사내 git만 OK |
| `confidential` | 기밀·개인정보 포함 | commit 금지 — 파일명 `*-confidential.md` 필수 |

`public` 등급은 회사 환경에서 사용하지 않는다. 애매하면 `confidential` 로 격상.

### confidence 기준

| 값 | 기준 |
|---|---|
| `high` | 복수의 신뢰할 수 있는 출처로 검증됨 |
| `medium` | 단일 출처이거나 직접 확인 필요 |
| `low` | 추론·추측 포함 — 출처를 명시하거나 삭제 제안 대상 |

## 문서 본문 구조

```markdown
# 제목

한 문단 요약 — 이 문서가 무엇인지 한눈에 파악 가능하게.

## 핵심 내용
## 세부 사항 (필요 시)
## 관련 맥락
## 변경 이력
- YYYY-MM-DD: 최초 생성 (출처: ...)
```

## 파일 명명 규칙

- 영문 소문자 + 하이픈: `kebab-case.md`
- 한국어 주제라도 파일명은 영문
- confidential 문서는 반드시 `-confidential.md` 접미사

## 업데이트 정책

1. **기존 문서 우선**: 새 자료가 들어오면 새 문서보다 기존 문서 업데이트를 먼저 고려
2. **분기 기준**: 하나의 문서가 500줄을 넘으면 주제별로 분리
3. **병합 기준**: 200줄 미만 문서가 3개 이상 유사 주제면 병합 고려
4. **삭제 금지**: 오래된 정보는 삭제 대신 `~~취소선~~` 처리 후 이유 기록
5. **index 다이어트**: wiki/index.md 는 문서당 제목 한 줄만 — 매 세션 주입되므로 비대화 금지
