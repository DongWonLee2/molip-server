---
paths:
  - "src/main/java/**/api/**/*.java"
  - "src/main/java/**/*Controller.java"
  - "src/main/java/**/global/error/**/*.java"
  - "openapi/**/*.yaml"
---

# API 규칙

## 계약

- `openapi/openapi.yaml`이 유일한 기준이다. 엔드포인트를 추가하거나 바꾸면 같은 PR에서 이 파일을 먼저 고친다.
- 이미 공개된 필드의 이름, 타입, 의미는 바꾸지 않는다. 새 필드를 추가하고 기존 필드는 `deprecated: true`로 표시한다.

## URI와 메서드

- 경로는 `/api/v1/` 아래 복수형 명사, kebab-case: `/api/v1/tasks/{taskId}/steps`
- 조회 GET, 생성 POST(201 + `Location`), 부분 수정 PATCH, 삭제 DELETE(204)
- 상태 전이는 동작 하위 리소스로 표현한다: `POST /api/v1/sessions/{id}/pause`, `/resume`, `/break`, `/complete`, `/abandon`
- 다른 사용자의 리소스 id를 path로 받더라도 소유자 확인은 서비스 계층에서 한다. 인증 사용자는 `@AuthenticationPrincipal`로만 얻는다.

## 응답과 에러

- 성공 응답은 DTO를 그대로 반환한다. 공통 래퍼로 감싸지 않는다.
- 에러는 RFC 9457 Problem Details(`application/problem+json`, Spring `ProblemDetail`)로 반환하고 `code` 확장 필드에 `ErrorCode` 이름을 넣는다. 예: `SESSION_ALREADY_RUNNING`
- 상태코드
  - 400: 요청 형식 오류, Bean Validation 실패
  - 401: 인증 없음 또는 토큰 만료
  - 403: 인증됐지만 권한 없음
  - 404: 리소스 없음 (남의 리소스도 존재를 드러내지 않도록 404)
  - 409: 현재 상태와 충돌 (진행 중 세션 존재, 정원 마감)
  - 422: 형식은 맞지만 도메인 규칙 위반 (집중 단위 범위 밖)
  - 429: 호출 한도 초과 (AI 쪼개기)
- 예상하지 못한 예외는 500과 일반 메시지만 반환하고, 상세는 traceId와 함께 로그에 남긴다.

## 목록과 시간

- 목록은 커서 페이지네이션: 요청 `?cursor=&size=20`, 응답 `{ "items": [], "nextCursor": "...", "hasNext": true }`. `size` 최대 50. offset 방식은 쓰지 않는다.
- 시각은 ISO-8601 UTC(`Instant`)로 주고받는다. 날짜 경계(오늘, 이번 주) 계산만 사용자 타임존(기본 Asia/Seoul)으로 한다.
- 기간 값(집중 단위, 쉬는 시간)은 분 단위 정수로 받는다: `focusMinutes`, `breakMinutes`

## DTO와 컨트롤러

- 요청, 응답 DTO는 `record`로 만들고 엔티티를 직접 노출하지 않는다.
- 요청 DTO에 Bean Validation을 붙이고, 컨트롤러는 검증, 변환, 위임만 한다. 비즈니스 로직과 `@Transactional`은 application 계층에 둔다.
- 컨트롤러를 추가하거나 바꾸면 해당 슬라이스 테스트(`@WebMvcTest`)도 같이 바꾼다.
