# Molip (몰입)

쇼츠에 집중력을 뺏긴 사람을 위한 집중 서비스의 백엔드. AI 코치 Jev가 지금 할 일 하나를 골라 주고(Jev Pick), 사용자가 정한 집중 단위로 할 일을 쪼개 주고, 집중과 휴식 세션, 한 줄 작업 기록, 알림으로 끝까지 하게 돕는다.

## 개요

- 스택: Java 21, Spring Boot 4.1, Spring Data JPA, QueryDSL, Spring Security(JWT, Google OAuth2), Spring AI 2.0, MySQL 8.4, Redis, Flyway. v1.0부터 Kafka, SSE.
- 이 레포는 백엔드만 담는다. 프론트는 별도 레포 `molip-web`(React + Vite SPA, PWA)이고 `openapi/openapi.yaml`을 복사해 타입을 생성한다.
- 릴리스: v0.1 할 일, 설정, AI 쪼개기, Jev Pick / v0.2 세션, 작업 기록, 알림 / v0.3 통계, 친구 피드 / v0.4 공개 배포 / v1.0 집중방, 선착순 챌린지, 리그
- 로컬 인프라는 Docker Compose(MySQL, Redis), 운영은 AWS EC2 + RDS, Nginx Blue-Green.

### 디렉터리

```text
src/main/java/com/molip/
  {domain}/api          컨트롤러, 요청/응답 DTO
  {domain}/application  유스케이스, 트랜잭션 경계
  {domain}/domain       엔티티, 도메인 규칙, 이벤트
  {domain}/infra        JPA, Redis, 외부 API 어댑터
  global/               보안, 예외, 설정
src/main/resources/db/migration/  Flyway (V{n}__{설명}.sql)
openapi/openapi.yaml              API 계약 (프론트와 공유)
scripts/deploy/                   배포 스크립트
```

도메인: `task`(할 일, 스텝), `setting`(집중 단위, 쉬는 시간), `session`(집중, 휴식, 작업 기록), `pick`(Jev Pick), `notification`, `stats`, `social`(친구, 피드, 응원), `auth`.

## 주요 명령어

| 목적 | 명령 |
| --- | --- |
| 로컬 인프라 시작 | `docker compose up -d` |
| 로컬 실행 | `./gradlew bootRun --args='--spring.profiles.active=local'` |
| 전체 테스트 | `./gradlew test` |
| 일부 테스트 | `./gradlew test --tests "com.molip.session.*"` |
| 포맷 적용 | `./gradlew spotlessApply` |
| CI와 같은 검사 | `./gradlew check` |
| 빌드 | `./gradlew build` |

## 하네스 안내

- 주제별 규칙은 `.claude/rules/`에 있고, 해당 파일을 다룰 때 자동으로 읽힌다.
- 테스트와 빌드처럼 출력이 긴 작업은 `test-runner` 에이전트에 맡기고 요약만 받는다.
- 배포와 롤백은 `deploy` 스킬 절차를 따른다. 배포 명령은 사람 승인이 필요하다.
- 비밀 파일, 운영 설정, 커밋된 마이그레이션, 하네스 설정은 훅이 막는다. 막히면 우회하지 말고 사용자에게 알린다.
