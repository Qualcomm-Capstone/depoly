# SpeedCam GCE 수동 배포 가이드

## 목차
1. [사전 요구사항](#1-사전-요구사항)
2. [Artifact Registry 설정](#2-artifact-registry-설정)
3. [Docker 이미지 빌드 및 푸시](#3-docker-이미지-빌드-및-푸시)
4. [환경 설정 파일 준비](#4-환경-설정-파일-준비)
5. [Credentials 디렉토리 생성](#5-credentials-디렉토리-생성)
6. [MySQL Exporter 설정](#6-mysql-exporter-설정)
7. [인스턴스별 배포 순서](#7-인스턴스별-배포-순서)
8. [헬스체크 및 검증](#8-헬스체크-및-검증)
9. [롤백 절차](#9-롤백-절차)
10. [이미지 버전 동기화 체크리스트](#10-이미지-버전-동기화-체크리스트)
11. [트러블슈팅](#11-트러블슈팅)

---

## 1. 사전 요구사항

### 로컬 환경
- **gcloud CLI**: 설치 및 인증 완료
- **Docker**: 로컬에 설치되어 있어야 함
- **Git**: backend 레포지토리 클론 필요

```bash
# gcloud 설치 확인
gcloud version

# gcloud 인증
gcloud auth login
gcloud config set project <your-project-id>

# Docker 설치 확인
docker --version
```

### GCP 프로젝트
- GCE 인스턴스 6개 생성 완료
  - `speedcam-db` (MySQL)
  - `speedcam-mq` (RabbitMQ)
  - `speedcam-app` (Traefik + Django API)
  - `speedcam-ocr` (OCR Worker)
  - `speedcam-alert` (Alert Worker)
  - `speedcam-mon` (Monitoring Stack)
- VPC 네트워크 설정 완료 (내부 IP 통신 가능)
- 방화벽 규칙 설정 완료

### 인스턴스 정보 확인

```bash
# 인스턴스 내부 IP 확인
gcloud compute instances list --filter="name~speedcam" \
    --format="table(name, networkInterfaces[0].networkIP, networkInterfaces[0].accessConfigs[0].natIP)"
```

**예시 출력:**
```
NAME              INTERNAL_IP    EXTERNAL_IP
speedcam-db       10.178.0.11    34.xxx.xxx.xxx
speedcam-mq       10.178.0.12    34.xxx.xxx.xxx
speedcam-app      10.178.0.13    34.xxx.xxx.xxx
speedcam-ocr      10.178.0.14    34.xxx.xxx.xxx
speedcam-alert    10.178.0.15    34.xxx.xxx.xxx
speedcam-mon      10.178.0.20    34.xxx.xxx.xxx
```

---

## 2. Artifact Registry 설정

### 저장소 생성

```bash
# Artifact Registry 저장소 생성 (asia-northeast3 리전)
gcloud artifacts repositories create speedcam \
    --repository-format=docker \
    --location=asia-northeast3 \
    --description="SpeedCam Docker Images"

# 생성 확인
gcloud artifacts repositories list --location=asia-northeast3
```

### Docker 인증 설정

```bash
# Artifact Registry 인증 구성
gcloud auth configure-docker asia-northeast3-docker.pkg.dev
```

---

## 3. Docker 이미지 빌드 및 푸시

> **중요**: 이미지 빌드는 **backend 레포지토리**에서 수행합니다.

### 3.1 Backend 레포지토리로 이동

```bash
# backend 레포지토리 클론 (아직 없다면)
git clone <backend-repo-url>
cd <backend-repo-path>

# 최신 코드 풀
git checkout main
git pull origin main
```

### 3.2 환경 변수 설정

```bash
# Artifact Registry 경로 설정
export PROJECT_ID=<your-project-id>
export REGION=asia-northeast3
export ARTIFACT_REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/speedcam"

# 이미지 태그 설정 (버전 관리)
export IMAGE_TAG=$(date +%Y%m%d-%H%M%S)  # 예: 20260208-143052
# 또는 Git 커밋 해시 사용
# export IMAGE_TAG=$(git rev-parse --short HEAD)
```

### 3.3 이미지 빌드

```bash
# 1. speedcam-main 이미지 (Django API 서버)
docker build -f docker/main.Dockerfile \
    -t ${ARTIFACT_REGISTRY}/speedcam-main:${IMAGE_TAG} \
    -t ${ARTIFACT_REGISTRY}/speedcam-main:latest \
    .

# 2. speedcam-ocr 이미지 (OCR Worker)
docker build -f docker/ocr.Dockerfile \
    -t ${ARTIFACT_REGISTRY}/speedcam-ocr:${IMAGE_TAG} \
    -t ${ARTIFACT_REGISTRY}/speedcam-ocr:latest \
    .

# 3. speedcam-alert 이미지 (Alert Worker)
docker build -f docker/alert.Dockerfile \
    -t ${ARTIFACT_REGISTRY}/speedcam-alert:${IMAGE_TAG} \
    -t ${ARTIFACT_REGISTRY}/speedcam-alert:latest \
    .
```

### 3.4 이미지 푸시

```bash
# speedcam-main 푸시
docker push ${ARTIFACT_REGISTRY}/speedcam-main:${IMAGE_TAG}
docker push ${ARTIFACT_REGISTRY}/speedcam-main:latest

# speedcam-ocr 푸시
docker push ${ARTIFACT_REGISTRY}/speedcam-ocr:${IMAGE_TAG}
docker push ${ARTIFACT_REGISTRY}/speedcam-ocr:latest

# speedcam-alert 푸시
docker push ${ARTIFACT_REGISTRY}/speedcam-alert:${IMAGE_TAG}
docker push ${ARTIFACT_REGISTRY}/speedcam-alert:latest
```

### 3.5 푸시 확인

```bash
# 업로드된 이미지 확인
gcloud artifacts docker images list ${ARTIFACT_REGISTRY} --include-tags
```

---

## 4. 환경 설정 파일 준비

### 4.1 depoly 레포지토리로 이동

```bash
cd /path/to/depoly
```

### 4.2 env 파일 복사

```bash
# 환경 변수 템플릿 복사
cp env/hosts.env.example env/hosts.env
cp env/backend.env.example env/backend.env
cp env/mysql.env.example env/mysql.env
cp env/rabbitmq.env.example env/rabbitmq.env
```

### 4.3 hosts.env 수정

```bash
nano env/hosts.env
```

**수정 내용:**
```bash
# 인스턴스 내부 IP 설정 (실제 IP로 교체)
export DB_HOST=10.178.0.11
export MQ_HOST=10.178.0.12
export APP_HOST=10.178.0.13
export OCR_HOST=10.178.0.14
export ALERT_HOST=10.178.0.15
export MON_HOST=10.178.0.20

# Artifact Registry 경로 (your-project-id 교체)
export ARTIFACT_REGISTRY=asia-northeast3-docker.pkg.dev/<your-project-id>/speedcam

# RabbitMQ 비밀번호
export RABBITMQ_PASSWORD=<production-password>

# Grafana 비밀번호
export GRAFANA_PASSWORD=<grafana-admin-password>

# 도메인 설정 (선택사항 - 없으면 비워두기)
export DOMAIN=
# 도메인이 있다면: export DOMAIN=autonotify.store
export ACME_EMAIL=your-email@example.com
export TRAEFIK_AUTH_USER=admin:$$2y$$05$$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 4.4 backend.env 수정

```bash
nano env/backend.env
```

**수정 내용:**
```bash
# Django
SECRET_KEY=<production-secret-key-at-least-50-chars>
DJANGO_SETTINGS_MODULE=config.settings.prod
DEBUG=False

# Database (hosts.env의 DB_HOST IP로 교체)
DB_HOST=10.178.0.11
DB_PORT=3306
DB_USER=sa
DB_PASSWORD=<production-password>
DB_NAME=speedcam
DB_NAME_VEHICLES=speedcam_vehicles
DB_NAME_DETECTIONS=speedcam_detections
DB_NAME_NOTIFICATIONS=speedcam_notifications

# RabbitMQ / Celery (hosts.env의 MQ_HOST IP로 교체)
CELERY_BROKER_URL=amqp://sa:<password>@10.178.0.12:5672//
RABBITMQ_HOST=10.178.0.12
MQTT_PORT=1883
MQTT_USER=sa
MQTT_PASS=<password>

# GCS / Firebase
GOOGLE_APPLICATION_CREDENTIALS=/app/credentials/gcp-cloud-storage.json
FIREBASE_CREDENTIALS=/app/credentials/firebase-service-account.json

# Workers
OCR_CONCURRENCY=4
ALERT_CONCURRENCY=100
OCR_MOCK=false
FCM_MOCK=false

# Gunicorn
GUNICORN_WORKERS=4
GUNICORN_THREADS=2

# Logging
LOG_LEVEL=info

# CORS (프론트엔드 도메인 또는 IP)
CORS_ALLOWED_ORIGINS=http://localhost:3000

# OpenTelemetry (hosts.env의 MON_HOST IP로 교체)
OTEL_EXPORTER_OTLP_ENDPOINT=http://10.178.0.20:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_RESOURCE_ATTRIBUTES=service.namespace=speedcam,deployment.environment=prod
OTEL_TRACES_SAMPLER=parentbased_tracealways
OTEL_PYTHON_LOG_CORRELATION=true
```

### 4.5 mysql.env 수정

```bash
nano env/mysql.env
```

**수정 내용:**
```bash
MYSQL_ROOT_PASSWORD=<production-root-password>
MYSQL_USER=sa
MYSQL_PASSWORD=<production-password>
MYSQL_DATABASE=speedcam
```

### 4.6 rabbitmq.env 수정

```bash
nano env/rabbitmq.env
```

**수정 내용:**
```bash
RABBITMQ_DEFAULT_USER=sa
RABBITMQ_DEFAULT_PASS=<production-password>
RABBITMQ_DEFAULT_VHOST=/
```

### 4.7 setup-env.sh 실행

```bash
# hosts.env 로드 및 설정 파일 생성
source env/hosts.env
./scripts/setup-env.sh
```

**생성되는 파일:**
- `config/traefik/dynamic_conf.yml` (도메인 모드 또는 IP 모드)
- `config/monitoring/prometheus/prometheus.yml`
- `config/monitoring/promtail/promtail-config.yml`

---

## 5. Credentials 디렉토리 생성

### 5.1 GCS 서비스 계정 키 생성 (GCP Console에서)

1. **IAM 및 관리자 → 서비스 계정**으로 이동
2. 서비스 계정 생성: `speedcam-gcs-sa`
3. 역할 부여: **Storage 객체 관리자**
4. 키 생성 → JSON 다운로드 → `gcp-cloud-storage.json`으로 저장

### 5.2 Firebase 서비스 계정 키 생성 (Firebase Console에서)

1. **프로젝트 설정 → 서비스 계정**으로 이동
2. **새 비공개 키 생성** 클릭
3. JSON 다운로드 → `firebase-service-account.json`으로 저장

### 5.3 credentials 디렉토리 생성

```bash
# depoly 레포지토리에 credentials 디렉토리 생성
mkdir -p config/credentials

# 다운로드한 JSON 파일을 credentials 디렉토리로 이동
mv ~/Downloads/gcp-cloud-storage.json config/credentials/
mv ~/Downloads/firebase-service-account.json config/credentials/

# 권한 설정
chmod 600 config/credentials/*.json
```

**디렉토리 구조:**
```
config/
└── credentials/
    ├── gcp-cloud-storage.json
    └── firebase-service-account.json
```

---

## 6. MySQL Exporter 설정

### 6.1 MySQL Exporter 설정 파일 생성

```bash
# 디렉토리 생성
mkdir -p config/monitoring/mysqld-exporter

# 설정 파일 생성
nano config/monitoring/mysqld-exporter/.my.cnf
```

**파일 내용:**
```ini
[client]
user=sa
password=<production-password>
host=localhost
port=3306
```

### 6.2 권한 설정

```bash
chmod 600 config/monitoring/mysqld-exporter/.my.cnf
```

---

## 7. 인스턴스별 배포 순서

> **배포 순서**: DB → MQ → MON → APP → OCR → ALERT

### 공통 준비 작업

```bash
# 배포 디렉토리 압축 (로컬에서)
cd /path/to/depoly
tar -czf speedcam-deploy.tar.gz \
    compose/ \
    config/ \
    env/ \
    scripts/

# 압축 파일 확인
ls -lh speedcam-deploy.tar.gz
```

---

### 7.1 speedcam-db 배포

#### 1) SCP로 파일 전송

```bash
# 배포 파일 전송
gcloud compute scp speedcam-deploy.tar.gz speedcam-db:~/ --zone=asia-northeast3-a

# 또는 외부 IP 직접 사용
# scp speedcam-deploy.tar.gz username@34.xxx.xxx.xxx:~/
```

#### 2) SSH 접속 및 배포

```bash
# SSH 접속
gcloud compute ssh speedcam-db --zone=asia-northeast3-a
```

**인스턴스 내부 작업:**

```bash
# 압축 해제
tar -xzf speedcam-deploy.tar.gz

# Artifact Registry 인증
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 환경 변수 로드
source env/hosts.env

# Docker Compose 실행
docker compose -f compose/docker-compose.db.yml up -d

# 로그 확인
docker logs speedcam-mysql
docker logs speedcam-mysqld-exporter
docker logs speedcam-promtail
docker logs speedcam-cadvisor

# 헬스체크
docker ps
```

#### 3) MySQL 초기화 확인

```bash
# MySQL 접속 테스트
docker exec -it speedcam-mysql mysql -u sa -p

# SQL 실행 (MySQL 콘솔에서)
SHOW DATABASES;
USE speedcam;
SHOW TABLES;
EXIT;
```

#### 4) SSH 종료

```bash
exit
```

---

### 7.2 speedcam-mq 배포

#### 1) SCP로 파일 전송

```bash
gcloud compute scp speedcam-deploy.tar.gz speedcam-mq:~/ --zone=asia-northeast3-a
```

#### 2) SSH 접속 및 배포

```bash
gcloud compute ssh speedcam-mq --zone=asia-northeast3-a
```

**인스턴스 내부 작업:**

```bash
# 압축 해제
tar -xzf speedcam-deploy.tar.gz

# Artifact Registry 인증
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 환경 변수 로드
source env/hosts.env

# Docker Compose 실행
docker compose -f compose/docker-compose.mq.yml up -d

# 로그 확인
docker logs speedcam-rabbitmq
docker logs speedcam-promtail
docker logs speedcam-cadvisor

# 헬스체크
docker ps
```

#### 3) RabbitMQ 웹 UI 확인

```bash
# 브라우저에서 접속
# http://<speedcam-mq 외부 IP>:15672
# 로그인: sa / <production-password>
```

#### 4) SSH 종료

```bash
exit
```

---

### 7.3 speedcam-mon 배포

#### 1) SCP로 파일 전송

```bash
gcloud compute scp speedcam-deploy.tar.gz speedcam-mon:~/ --zone=asia-northeast3-a
```

#### 2) SSH 접속 및 배포

```bash
gcloud compute ssh speedcam-mon --zone=asia-northeast3-a
```

**인스턴스 내부 작업:**

```bash
# 압축 해제
tar -xzf speedcam-deploy.tar.gz

# Artifact Registry 인증
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 환경 변수 로드
source env/hosts.env

# Docker Compose 실행
docker compose -f compose/docker-compose.mon.yml up -d

# 로그 확인
docker logs speedcam-prometheus
docker logs speedcam-grafana
docker logs speedcam-loki
docker logs speedcam-jaeger
docker logs speedcam-otel-collector
docker logs speedcam-celery-exporter
docker logs speedcam-promtail
docker logs speedcam-cadvisor

# 헬스체크
docker ps
```

#### 3) Grafana 웹 UI 확인

```bash
# 브라우저에서 접속
# http://<speedcam-mon 외부 IP>:3000
# 로그인: admin / <GRAFANA_PASSWORD>
```

#### 4) SSH 종료

```bash
exit
```

---

### 7.4 speedcam-app 배포

#### 1) SCP로 파일 전송

```bash
gcloud compute scp speedcam-deploy.tar.gz speedcam-app:~/ --zone=asia-northeast3-a
```

#### 2) SSH 접속 및 배포

```bash
gcloud compute ssh speedcam-app --zone=asia-northeast3-a
```

**인스턴스 내부 작업:**

```bash
# 압축 해제
tar -xzf speedcam-deploy.tar.gz

# Artifact Registry 인증
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 환경 변수 로드
source env/hosts.env

# Docker Compose 실행
docker compose -f compose/docker-compose.app.yml up -d

# 로그 확인
docker logs speedcam-traefik
docker logs speedcam-main
docker logs speedcam-flower
docker logs speedcam-promtail
docker logs speedcam-cadvisor

# 헬스체크
docker ps
```

#### 3) API 헬스체크

```bash
# Django API 헬스체크
curl http://localhost:8000/health/

# Flower 접속 확인 (브라우저)
# http://<speedcam-app 외부 IP>:5555
```

#### 4) SSH 종료

```bash
exit
```

---

### 7.5 speedcam-ocr 배포

#### 1) SCP로 파일 전송

```bash
gcloud compute scp speedcam-deploy.tar.gz speedcam-ocr:~/ --zone=asia-northeast3-a
```

#### 2) SSH 접속 및 배포

```bash
gcloud compute ssh speedcam-ocr --zone=asia-northeast3-a
```

**인스턴스 내부 작업:**

```bash
# 압축 해제
tar -xzf speedcam-deploy.tar.gz

# Artifact Registry 인증
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 환경 변수 로드
source env/hosts.env

# Docker Compose 실행
docker compose -f compose/docker-compose.ocr.yml up -d

# 로그 확인
docker logs speedcam-ocr
docker logs speedcam-promtail
docker logs speedcam-cadvisor

# 헬스체크
docker ps
```

#### 3) Worker 상태 확인

```bash
# Flower에서 OCR Worker 확인
# http://<speedcam-app 외부 IP>:5555
# Workers 탭에서 "ocr@<hostname>" 활성화 확인
```

#### 4) SSH 종료

```bash
exit
```

---

### 7.6 speedcam-alert 배포

#### 1) SCP로 파일 전송

```bash
gcloud compute scp speedcam-deploy.tar.gz speedcam-alert:~/ --zone=asia-northeast3-a
```

#### 2) SSH 접속 및 배포

```bash
gcloud compute ssh speedcam-alert --zone=asia-northeast3-a
```

**인스턴스 내부 작업:**

```bash
# 압축 해제
tar -xzf speedcam-deploy.tar.gz

# Artifact Registry 인증
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 환경 변수 로드
source env/hosts.env

# Docker Compose 실행
docker compose -f compose/docker-compose.alert.yml up -d

# 로그 확인
docker logs speedcam-alert
docker logs speedcam-promtail
docker logs speedcam-cadvisor

# 헬스체크
docker ps
```

#### 3) Worker 상태 확인

```bash
# Flower에서 Alert Worker 확인
# http://<speedcam-app 외부 IP>:5555
# Workers 탭에서 "alert@<hostname>" 활성화 확인
```

#### 4) SSH 종료

```bash
exit
```

---

## 8. 헬스체크 및 검증

### 8.1 MySQL 헬스체크

```bash
# speedcam-db에 SSH 접속
gcloud compute ssh speedcam-db --zone=asia-northeast3-a

# MySQL 접속 테스트
docker exec -it speedcam-mysql mysql -u sa -p -e "SELECT 1;"

# 데이터베이스 확인
docker exec -it speedcam-mysql mysql -u sa -p -e "SHOW DATABASES;"

# MySQL Exporter 메트릭 확인
curl http://localhost:9104/metrics | grep mysql_up
# 출력: mysql_up 1
```

### 8.2 RabbitMQ 헬스체크

```bash
# speedcam-mq에 SSH 접속
gcloud compute ssh speedcam-mq --zone=asia-northeast3-a

# RabbitMQ 상태 확인
docker exec speedcam-rabbitmq rabbitmq-diagnostics status

# 플러그인 확인 (MQTT, Prometheus 활성화 확인)
docker exec speedcam-rabbitmq rabbitmq-plugins list

# 웹 UI 접속
# http://<speedcam-mq 외부 IP>:15672
```

### 8.3 Django API 헬스체크

```bash
# speedcam-app에 SSH 접속
gcloud compute ssh speedcam-app --zone=asia-northeast3-a

# API 헬스체크 엔드포인트
curl http://localhost:8000/health/
# 기대 출력: {"status": "ok"}

# Django 마이그레이션 확인
docker exec speedcam-main python manage.py showmigrations

# Django 관리자 생성 (필요시)
docker exec -it speedcam-main python manage.py createsuperuser
```

### 8.4 Traefik 헬스체크

```bash
# speedcam-app에 SSH 접속
gcloud compute ssh speedcam-app --zone=asia-northeast3-a

# Traefik 대시보드 확인
curl http://localhost:8080/api/http/routers
curl http://localhost:8080/api/http/services

# 웹 브라우저에서
# http://<speedcam-app 외부 IP>:8080/dashboard/
```

### 8.5 Celery Workers 헬스체크

```bash
# Flower 웹 UI 접속
# http://<speedcam-app 외부 IP>:5555

# Workers 탭 확인:
# - ocr@speedcam-ocr (4 concurrency)
# - alert@speedcam-alert (100 concurrency)
```

### 8.6 Prometheus 헬스체크

```bash
# speedcam-mon에 SSH 접속
gcloud compute ssh speedcam-mon --zone=asia-northeast3-a

# Prometheus 타겟 확인
curl http://localhost:9090/api/v1/targets | jq .

# 웹 브라우저에서
# http://<speedcam-mon 외부 IP>:9090
# Status → Targets → 모든 타겟 UP 확인
```

### 8.7 Grafana 헬스체크

```bash
# 웹 브라우저에서 접속
# http://<speedcam-mon 외부 IP>:3000
# 로그인: admin / <GRAFANA_PASSWORD>

# 데이터 소스 확인:
# Configuration → Data Sources
# - Prometheus (http://localhost:9090)
# - Loki (http://localhost:3100)
# - Jaeger (http://localhost:16686)
```

### 8.8 전체 시스템 헬스체크 스크립트

**로컬에서 실행:**

```bash
#!/bin/bash
# health-check.sh

INSTANCES=(
  "speedcam-db:10.178.0.11"
  "speedcam-mq:10.178.0.12"
  "speedcam-app:10.178.0.13"
  "speedcam-ocr:10.178.0.14"
  "speedcam-alert:10.178.0.15"
  "speedcam-mon:10.178.0.20"
)

echo "========================================="
echo " SpeedCam 전체 헬스체크"
echo "========================================="

for instance in "${INSTANCES[@]}"; do
  name="${instance%%:*}"
  ip="${instance##*:}"

  echo ""
  echo "[$name] 컨테이너 상태 확인..."
  gcloud compute ssh $name --zone=asia-northeast3-a --command="docker ps --format 'table {{.Names}}\t{{.Status}}'"
done

echo ""
echo "========================================="
echo " 완료"
echo "========================================="
```

**실행:**

```bash
chmod +x health-check.sh
./health-check.sh
```

---

## 9. 롤백 절차

### 9.1 특정 이미지 버전으로 롤백

```bash
# 1. 롤백할 이미지 태그 확인
gcloud artifacts docker images list ${ARTIFACT_REGISTRY}/speedcam-main --include-tags

# 2. 인스턴스에 SSH 접속 (예: speedcam-app)
gcloud compute ssh speedcam-app --zone=asia-northeast3-a

# 3. 환경 변수 수정 (이미지 태그 변경)
nano env/hosts.env
# export ARTIFACT_REGISTRY=asia-northeast3-docker.pkg.dev/<project-id>/speedcam:20260207-120000

# 4. Docker Compose 재시작
source env/hosts.env
docker compose -f compose/docker-compose.app.yml pull
docker compose -f compose/docker-compose.app.yml up -d

# 5. 로그 확인
docker logs speedcam-main
```

### 9.2 전체 서비스 롤백

```bash
# 역순으로 롤백: ALERT → OCR → APP → MON → MQ → DB
# 각 인스턴스에서:

docker compose -f compose/docker-compose.<service>.yml down
docker compose -f compose/docker-compose.<service>.yml up -d
```

### 9.3 데이터 백업 (롤백 전)

```bash
# MySQL 백업
gcloud compute ssh speedcam-db --zone=asia-northeast3-a
docker exec speedcam-mysql mysqldump -u sa -p --all-databases > /tmp/backup-$(date +%Y%m%d).sql

# 백업 파일 다운로드
gcloud compute scp speedcam-db:/tmp/backup-*.sql ~/backups/ --zone=asia-northeast3-a
```

---

## 10. 이미지 버전 동기화 체크리스트

### 10.1 모니터링 이미지 버전 확인

**backend 레포지토리와 depoly 레포지토리의 모니터링 이미지 버전이 일치해야 합니다.**

#### backend/docker/monitoring/docker-compose.yml

```bash
# backend 레포지토리에서 확인
cd <backend-repo-path>
grep 'image:' docker/monitoring/docker-compose.yml
```

**예시 출력:**
```yaml
prometheus: prom/prometheus:v2.51.2
grafana: grafana/grafana:10.4.2
loki: grafana/loki:2.9.6
promtail: grafana/promtail:2.9.6
jaeger: jaegertracing/all-in-one:1.57
otel-collector: otel/opentelemetry-collector-contrib:0.98.0
cadvisor: gcr.io/cadvisor/cadvisor:v0.49.1
mysqld-exporter: prom/mysqld-exporter:v0.15.1
celery-exporter: danihodovic/celery-exporter:0.10.3
```

#### depoly/compose/docker-compose.mon.yml

```bash
# depoly 레포지토리에서 확인
cd /path/to/depoly
grep 'image:' compose/docker-compose.mon.yml
grep 'image:' compose/docker-compose.db.yml
grep 'image:' compose/docker-compose.mq.yml
grep 'image:' compose/docker-compose.app.yml
grep 'image:' compose/docker-compose.ocr.yml
grep 'image:' compose/docker-compose.alert.yml
```

### 10.2 버전 불일치 해결

**버전이 다르면 depoly 레포지토리를 backend 기준으로 업데이트:**

```bash
# depoly 레포지토리에서
nano compose/docker-compose.mon.yml
# 이미지 버전을 backend와 동일하게 수정

# 변경사항 커밋
git add compose/docker-compose.mon.yml
git commit -m "chore: sync monitoring image versions with backend"
git push origin main
```

### 10.3 프로덕션 배포 전 체크리스트

- [ ] backend 레포지토리 최신 커밋 확인
- [ ] depoly 레포지토리 최신 커밋 확인
- [ ] 모니터링 이미지 버전 동기화 확인
- [ ] backend 이미지 빌드 및 푸시 완료
- [ ] env 파일 모두 설정 완료 (hosts.env, backend.env, mysql.env, rabbitmq.env)
- [ ] credentials 디렉토리 생성 완료 (GCS, Firebase JSON)
- [ ] MySQL Exporter .my.cnf 생성 완료
- [ ] setup-env.sh 실행 완료 (Traefik, Prometheus, Promtail 설정 생성)
- [ ] config/mysql/init.sql 확인 (최신 스키마)

---

## 11. 트러블슈팅

### 11.1 MySQL 컨테이너 시작 실패

**증상:**
```
speedcam-mysql exited with code 1
```

**해결:**

```bash
# 로그 확인
docker logs speedcam-mysql

# 일반적인 원인:
# 1. 비밀번호 환경 변수 누락 → env/mysql.env 확인
# 2. init.sql 문법 오류 → config/mysql/init.sql 확인
# 3. 볼륨 권한 문제 → sudo chown -R 999:999 /var/lib/docker/volumes/mysql_data
```

### 11.2 RabbitMQ 플러그인 활성화 실패

**증상:**
```
MQTT 포트 1883 연결 실패
```

**해결:**

```bash
# 컨테이너 재시작
docker restart speedcam-rabbitmq

# 플러그인 수동 활성화
docker exec speedcam-rabbitmq rabbitmq-plugins enable rabbitmq_mqtt rabbitmq_prometheus

# 확인
docker exec speedcam-rabbitmq rabbitmq-plugins list
```

### 11.3 Artifact Registry 인증 실패

**증상:**
```
Error response from daemon: unauthorized: You don't have the needed permissions
```

**해결:**

```bash
# gcloud 재인증
gcloud auth login
gcloud auth configure-docker asia-northeast3-docker.pkg.dev

# 서비스 계정 키 사용 (선택사항)
gcloud auth activate-service-account --key-file=<service-account-key.json>
```

### 11.4 Django API 500 에러

**증상:**
```
curl http://localhost:8000/health/
{"detail": "Internal Server Error"}
```

**해결:**

```bash
# Django 로그 확인
docker logs speedcam-main

# 일반적인 원인:
# 1. MySQL 연결 실패 → backend.env의 DB_HOST 확인
# 2. 마이그레이션 미실행 → docker exec speedcam-main python manage.py migrate
# 3. Credentials 누락 → config/credentials/*.json 확인
# 4. RabbitMQ 연결 실패 → backend.env의 CELERY_BROKER_URL 확인
```

### 11.5 Prometheus 타겟 DOWN

**증상:**
```
Prometheus 웹 UI에서 타겟이 DOWN 상태
```

**해결:**

```bash
# Prometheus 설정 확인
cat config/monitoring/prometheus/prometheus.yml

# 타겟 인스턴스에서 Exporter 상태 확인
docker ps | grep exporter
docker logs speedcam-mysqld-exporter
docker logs speedcam-cadvisor

# 네트워크 연결 확인
curl http://<타겟 IP>:9104/metrics  # mysqld-exporter
curl http://<타겟 IP>:8080/metrics  # cadvisor
```

### 11.6 Celery Worker 등록 안 됨

**증상:**
```
Flower에서 Worker가 보이지 않음
```

**해결:**

```bash
# Worker 로그 확인
docker logs speedcam-ocr
docker logs speedcam-alert

# 일반적인 원인:
# 1. RabbitMQ 연결 실패 → backend.env의 CELERY_BROKER_URL 확인
# 2. Worker 컨테이너 종료 → docker ps 확인
# 3. Celery 설정 오류 → docker logs에서 traceback 확인

# Worker 재시작
docker restart speedcam-ocr
docker restart speedcam-alert
```

### 11.7 Traefik HTTPS 인증서 발급 실패

**증상:**
```
도메인 접속 시 "Your connection is not private" 경고
```

**해결:**

```bash
# Traefik 로그 확인
docker logs speedcam-traefik

# 일반적인 원인:
# 1. DNS A 레코드 미설정 → 도메인이 speedcam-app 외부 IP를 가리키는지 확인
# 2. 80 포트 막힘 → 방화벽 규칙 확인 (Let's Encrypt HTTP-01 Challenge)
# 3. ACME 이메일 미설정 → config/traefik/traefik.yml 확인

# 인증서 수동 재발급
docker exec speedcam-traefik rm -rf /etc/traefik/certs/*
docker restart speedcam-traefik
```

---

## 부록: 도메인 모드 DNS 설정

**도메인을 사용하는 경우 (예: autonotify.store):**

| 서브도메인 | 타입 | 값 | 설명 |
|-----------|------|-----|------|
| api.autonotify.store | A | speedcam-app 외부 IP | Django API |
| flower.autonotify.store | A | speedcam-app 외부 IP | Celery 모니터링 |
| grafana.autonotify.store | A | speedcam-app 외부 IP | Grafana (Traefik으로 프록시) |
| rabbitmq.autonotify.store | A | speedcam-app 외부 IP | RabbitMQ 관리 (Traefik으로 프록시) |
| traefik.autonotify.store | A | speedcam-app 외부 IP | Traefik 대시보드 |

**Traefik이 모든 서브도메인을 내부 서비스로 라우팅합니다.**

---

## 결론

이 가이드를 통해 6개의 GCE 인스턴스에 SpeedCam 프로젝트를 수동으로 배포할 수 있습니다. 배포 후 반드시 헬스체크를 수행하여 모든 서비스가 정상 작동하는지 확인하세요.

**다음 단계:**
- CI/CD 파이프라인 구축 (GitHub Actions)
- 자동 배포 스크립트 작성
- 모니터링 대시보드 커스터마이징
- 백업 자동화 (MySQL, 설정 파일)

**문의:**
- Backend: <backend-repo-url>
- Deploy: <deploy-repo-url>
