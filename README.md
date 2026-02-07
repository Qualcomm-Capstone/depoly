# SpeedCam Deploy

6대 GCE 인스턴스의 프로덕션 compose, 인프라 설정, 배포 파이프라인을 조율한다.

## 디렉토리 구조

```
depoly/
├── compose/           # 인스턴스별 docker-compose 파일
├── config/            # Traefik, 모니터링, MySQL 설정
├── env/               # 환경변수 템플릿 (*.env.example)
├── scripts/           # 배포 스크립트
├── docs/              # 배포 가이드
└── .github/workflows/ # CI/CD 파이프라인
```

## 배포 대상 인스턴스

| 인스턴스명 | Zone | 역할 | 상태 |
|-----------|------|------|------|
| api-primary | us-central1-a | API 서버 (Primary) | Active |
| api-secondary | us-central1-b | API 서버 (Secondary) | Active |
| web-primary | us-east1-b | Web 서버 (Primary) | Active |
| web-secondary | us-east1-c | Web 서버 (Secondary) | Active |
| db-master | us-central1-a | MySQL Master | Active |
| db-replica | us-central1-c | MySQL Replica | Active |

## 빠른 시작

### 전체 배포

```bash
./scripts/deploy-all.sh <zone>
```

예시:
```bash
./scripts/deploy-all.sh us-central1-a
```

### 개별 배포

각 인스턴스 배포는 `docs/manual-deploy.md` 참조

## 저장소 책임 범위

이 저장소(depoly)는 다음을 관리한다:

- **Docker Compose 파일**: 각 GCE 인스턴스에서 실행되는 서비스 정의
- **인프라 설정**: Traefik (리버스 프록시), 모니터링 스택 (Prometheus, Grafana), MySQL 설정
- **환경 설정**: 환경변수 템플릿 및 설정 파일
- **배포 자동화**: 배포 스크립트 및 CI/CD 파이프라인
- **배포 문서**: 수동 배포 가이드 및 트러블슈팅

## 상세 배포 가이드

자세한 배포 절차는 [`docs/manual-deploy.md`](./docs/manual-deploy.md)를 참조하시기 바랍니다.