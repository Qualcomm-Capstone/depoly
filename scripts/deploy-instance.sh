#!/usr/bin/env bash
# ===========================================
# 단일 인스턴스 배포 스크립트
# ===========================================
# 사용법: ./scripts/deploy-instance.sh <instance-name> <zone>
# 예시: ./scripts/deploy-instance.sh speedcam-app asia-northeast3-a
#
# 기능:
# - 인스턴스 이름을 기반으로 docker-compose 파일 자동 매핑
# - depoly/ 디렉토리 전체를 인스턴스에 SCP
# - 인스턴스에 SSH 접속하여 Docker 컨테이너 배포
# ===========================================

set -euo pipefail

# ===== 색상 정의 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===== 함수: 색상 출력 =====
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ===== 인자 검증 =====
if [ $# -ne 2 ]; then
    print_error "인자가 잘못되었습니다."
    echo "사용법: $0 <instance-name> <zone>"
    echo "예시: $0 speedcam-app asia-northeast3-a"
    exit 1
fi

INSTANCE_NAME="$1"
ZONE="$2"

# ===== 디렉토리 설정 =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

print_info "배포 디렉토리: ${DEPLOY_DIR}"
print_info "대상 인스턴스: ${INSTANCE_NAME}"
print_info "존(Zone): ${ZONE}"

# ===== 인스턴스 이름 → 역할(role) 매핑 =====
case "$INSTANCE_NAME" in
    speedcam-app)
        ROLE="app"
        NEEDS_PULL=true
        ;;
    speedcam-db)
        ROLE="db"
        NEEDS_PULL=false
        ;;
    speedcam-mq)
        ROLE="mq"
        NEEDS_PULL=false
        ;;
    speedcam-mon)
        ROLE="mon"
        NEEDS_PULL=false
        ;;
    speedcam-ocr)
        ROLE="ocr"
        NEEDS_PULL=true
        ;;
    speedcam-alert)
        ROLE="alert"
        NEEDS_PULL=true
        ;;
    *)
        print_error "알 수 없는 인스턴스 이름: ${INSTANCE_NAME}"
        echo "지원되는 인스턴스: speedcam-app, speedcam-db, speedcam-mq, speedcam-mon, speedcam-ocr, speedcam-alert"
        exit 1
        ;;
esac

COMPOSE_FILE="docker-compose.${ROLE}.yml"
print_info "역할(ROLE): ${ROLE}"
print_info "Compose 파일: compose/${COMPOSE_FILE}"

# ===== Compose 파일 존재 확인 =====
if [ ! -f "${DEPLOY_DIR}/compose/${COMPOSE_FILE}" ]; then
    print_error "Compose 파일이 존재하지 않습니다: ${DEPLOY_DIR}/compose/${COMPOSE_FILE}"
    exit 1
fi

# ===== 인스턴스 존재 확인 =====
print_info "인스턴스 존재 여부 확인 중..."
if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &>/dev/null; then
    print_error "인스턴스를 찾을 수 없습니다: ${INSTANCE_NAME} (zone: ${ZONE})"
    exit 1
fi
print_success "인스턴스 확인 완료"

# ===== 1. SCP로 depoly/ 디렉토리 전송 =====
print_info "=========================================="
print_info "Step 1: depoly/ 디렉토리 전송 중..."
print_info "=========================================="

gcloud compute scp --recurse \
    --zone="$ZONE" \
    "${DEPLOY_DIR}" \
    "${INSTANCE_NAME}:~/" \
    || { print_error "SCP 전송 실패"; exit 1; }

print_success "depoly/ 디렉토리 전송 완료"

# ===== 2. SSH로 배포 명령 실행 =====
print_info "=========================================="
print_info "Step 2: 인스턴스에서 배포 실행 중..."
print_info "=========================================="

# 배포 스크립트 생성 (heredoc 사용)
DEPLOY_SCRIPT=$(cat <<EOF
set -euo pipefail

echo "[INFO] Docker 인증 설정 중..."
gcloud auth configure-docker asia-northeast3-docker.pkg.dev --quiet

cd ~/depoly || { echo "[ERROR] ~/depoly 디렉토리 이동 실패"; exit 1; }

echo "[INFO] 환경 변수 로드 중..."
if [ ! -f env/hosts.env ]; then
    echo "[ERROR] env/hosts.env 파일이 없습니다."
    exit 1
fi
source env/hosts.env

echo "[INFO] 환경 설정 스크립트 실행 중..."
./scripts/setup-env.sh || { echo "[ERROR] setup-env.sh 실행 실패"; exit 1; }

echo "[INFO] 배포 역할(ROLE): ${ROLE}"
echo "[INFO] Compose 파일: compose/${COMPOSE_FILE}"

# Artifact Registry 이미지를 사용하는 경우만 pull
if [ "${NEEDS_PULL}" = "true" ]; then
    echo "[INFO] Docker 이미지 pull 중..."
    docker compose -f compose/${COMPOSE_FILE} pull || { echo "[ERROR] docker compose pull 실패"; exit 1; }
else
    echo "[INFO] 로컬 이미지 사용 (pull 생략)"
fi

echo "[INFO] Docker 컨테이너 시작 중..."
docker compose -f compose/${COMPOSE_FILE} up -d || { echo "[ERROR] docker compose up 실패"; exit 1; }

echo "[INFO] 컨테이너 상태 확인 중..."
docker compose -f compose/${COMPOSE_FILE} ps

echo "[SUCCESS] ${INSTANCE_NAME} 배포 완료!"
EOF
)

# SSH로 배포 스크립트 실행
gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --command="$DEPLOY_SCRIPT" \
    || { print_error "SSH 배포 명령 실행 실패"; exit 1; }

# ===== 완료 메시지 =====
print_success "=========================================="
print_success "${INSTANCE_NAME} 배포 성공!"
print_success "=========================================="
print_info "역할: ${ROLE}"
print_info "Compose 파일: compose/${COMPOSE_FILE}"
print_info "확인 명령: gcloud compute ssh ${INSTANCE_NAME} --zone=${ZONE} --command='docker ps'"
