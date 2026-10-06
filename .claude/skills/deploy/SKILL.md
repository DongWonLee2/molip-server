---
name: deploy
description: Molip API를 운영 EC2에 Blue-Green 방식으로 수동 배포하거나, 직전 버전으로 롤백하거나, 배포 상태를 확인할 때 쓴다. 평소 배포는 main 머지 시 GitHub Actions가 하므로 사용자가 배포, 롤백, 배포 상태를 직접 요청했을 때만 쓴다.
argument-hint: "[deploy <git-sha> | rollback | status]"
---

# Molip 배포 절차

요청: $ARGUMENTS

## 전제

- 운영은 EC2 1대에서 Docker로 돌고, Nginx가 blue(8081)와 green(8082) 중 활성 쪽으로 프록시한다.
- 스크립트는 `scripts/deploy/`에 있다: `deploy.sh <sha>`, `switch.sh`, `rollback.sh`, `status.sh`
- 스크립트가 아직 없으면 아무것도 실행하지 말고 "배포 스크립트가 아직 없다"고 알린 뒤 멈춘다.
- `scripts/deploy/*` 실행은 settings.json에서 사람 승인(ask)을 받게 되어 있다. 승인 요청 전에 무엇을 왜 실행하는지 한 줄로 말한다.

## 공통 사전 확인

1. 사용자가 이번 대화에서 배포, 롤백, 상태 확인 중 하나를 직접 요청했는지 확인한다. 아니면 멈춘다.
2. `git status`로 작업 트리가 깨끗한지, 현재 브랜치가 main인지 확인한다.
3. `gh run list --branch main --limit 1`로 최신 CI가 성공인지 확인한다. 실패거나 진행 중이면 멈춘다.

## deploy <git-sha>

1. `scripts/deploy/status.sh`로 현재 활성 색과 sha를 기록한다. 이 값이 롤백 기준이다.
2. `scripts/deploy/deploy.sh <sha>`로 비활성 색에 새 컨테이너를 띄운다.
3. `/actuator/health/readiness`가 UP이 될 때까지 최대 60초 기다린다. 실패하면 전환하지 않고 멈춘다.
4. 스모크 확인: 비활성 포트로 `GET /api/v1/health`와 로그인 없이 되는 조회 1개를 호출한다.
5. `scripts/deploy/switch.sh`로 Nginx upstream을 새 색으로 바꾸고 reload한다.
6. 전환 후 5분 동안 5xx 비율과 p95를 확인한다(Grafana 또는 `status.sh --metrics`). 평소보다 확실히 나쁘면 바로 롤백 절차로 간다.
7. 이전 색 컨테이너는 지우지 않는다. 롤백용으로 남겨 둔다.

## rollback

1. `scripts/deploy/rollback.sh`로 직전 색으로 Nginx를 되돌린다.
2. readiness와 스모크 확인을 다시 한다.
3. DB 마이그레이션은 되돌리지 않는다. 이번 배포에 스키마 변경이 있었다면 사용자에게 알리고 멈춘다. 스키마 변경은 항상 이전 버전과 호환되게(expand, contract 순서로) 만든다.

## status

`scripts/deploy/status.sh`로 활성 색, 색별 sha, 헬스를 확인한다.

## 보고 형식

다섯 줄 이내로 보고한다: 동작(deploy, rollback, status), 이전 sha, 현재 sha, 헬스와 스모크 결과, 관찰 결과 또는 멈춘 이유.

## 하지 않는 것

- 운영 DB에 직접 접속해 데이터를 고치지 않는다.
- `docker system prune`, 보안 그룹 변경, 인스턴스 재시작을 하지 않는다.
- 실패한 단계를 반복 재시도하지 않는다. 한 번 실패하면 로그 요약과 함께 멈춘다.
