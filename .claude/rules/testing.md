---
paths:
  - "src/test/**/*.java"
  - "src/testFixtures/**/*.java"
---

# 테스트 규칙

## 종류

- 단위: 도메인 규칙, Jev Pick 점수, 세션 상태 머신. Spring 없이 JUnit 5 + AssertJ로 쓴다.
- 슬라이스: 컨트롤러는 `@WebMvcTest`, 쿼리는 `@DataJpaTest` + Testcontainers MySQL
- 통합: `@SpringBootTest` + Testcontainers(MySQL, Redis). H2는 쓰지 않는다. MySQL 방언과 락 동작이 다르다.
- 클래스 이름은 `{대상}Test`, 통합은 `{대상}IntegrationTest`. `@DisplayName`에 한국어로 행동을 적는다. 예: "진행 중인 세션이 있으면 새 세션을 시작할 수 없다"
- 본문은 given / when / then 순서로 나눈다.

## 외부 의존성

- LLM API를 실제로 호출하지 않는다. WireMock이나 테스트용 스텁으로 정상 응답, 깨진 JSON, 타임아웃을 각각 만든다.
- Web Push 발송은 가짜 발송기로 바꾸고 호출 여부와 내용만 검증한다.
- 현재 시각은 `Clock`을 주입해서 쓴다. 테스트에서 `Instant.now()`에 기대지 않는다.
- 비동기 결과는 `Thread.sleep` 대신 Awaitility로 기다린다.

## 동시성 테스트

- `ExecutorService`와 `CountDownLatch`로 요청을 한 번에 출발시킨다. 스레드 수와 요청 수는 상수로 드러낸다.
- 단언은 최종 상태로 한다. 예: 진행 중 세션 수가 정확히 1, 집중방 인원이 정원 이하, 포인트 적립이 1회
- 클래스 이름은 `{대상}ConcurrencyTest`로 지어 따로 돌릴 수 있게 한다.

## 격리와 데이터

- 테스트끼리 데이터를 공유하지 않는다. 필요한 데이터는 각 테스트가 픽스처 빌더로 만든다.
- 통합 테스트 정리는 테이블 truncate 유틸로 한다. 다른 스레드가 쓰는 테스트에서는 `@Transactional` 롤백이 보이지 않는다.

## 하지 말 것

- 실패하는 테스트를 통과시키려고 단언을 약하게 바꾸거나 `@Disabled`를 붙이지 않는다. 원인을 보고하고 멈춘다.
- 테스트 실행 결과를 통째로 읽지 않는다. 실행과 요약은 `test-runner` 에이전트에 맡긴다.
