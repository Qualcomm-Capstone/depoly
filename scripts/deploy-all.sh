#!/usr/bin/env bash
# ===========================================
# 전체 인스턴스 배포 스크립트
# ===========================================
# 사용법: ./scripts/deploy-all.sh <zone>
# 예시: ./scripts/deploy-all.sh asia-northeast3-a
#
# 기능:
# - 모든 인스턴스를 순서대로 배포 (DB → MQ → MON → APP → OCR → ALERT)
# - 각 배포 사이에 대기 시간을 두어 서비스가 안정화되도록 함
# - 배포 실패 시에도 계속 진행하고 최종 결과 요약 제공
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
if [ $# -ne 1 ]; then
    print_error "인자가 잘못되었습니다."
    echo "사용법: $0 <zone>"
    echo "예시: $0 asia-northeast3-a"
    exit 1
fi

ZONE="$1"

# ===== 디렉토리 설정 =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy-instance.sh"

# deploy-instance.sh 존재 확인
if [ ! -f "$DEPLOY_SCRIPT" ]; then
    print_error "deploy-instance.sh를 찾을 수 없습니다: ${DEPLOY_SCRIPT}"
    exit 1
fi

# 실행 권한 확인
if [ ! -x "$DEPLOY_SCRIPT" ]; then
    print_warning "deploy-instance.sh에 실행 권한 부여 중..."
    chmod +x "$DEPLOY_SCRIPT"
fi

print_info "=========================================="
print_info "전체 인스턴스 배포 시작"
print_info "=========================================="
print_info "존(Zone): ${ZONE}"
print_info "배포 순서: DB → MQ → MON → APP → OCR → ALERT"
echo ""

# ===== 배포 대상 인스턴스 목록 (순서 중요) =====
declare -a INSTANCES=(
    "speedcam-db"
    "speedcam-mq"
    "speedcam-mon"
    "speedcam-app"
    "speedcam-ocr"
    "speedcam-alert"
)

# ===== 대기 시간 설정 (초) =====
declare -A WAIT_TIME=(
    ["speedcam-db"]=30
    ["speedcam-mq"]=20
    ["speedcam-mon"]=20
    ["speedcam-app"]=15
    ["speedcam-ocr"]=15
    ["speedcam-alert"]=10
)

# ===== 배포 결과 추적 =====
declare -A DEPLOY_RESULTS=()

# ===== 각 인스턴스 배포 =====
for INSTANCE in "${INSTANCES[@]}"; do
    print_info "=========================================="
    print_info "배포 시작: ${INSTANCE}"
    print_info "=========================================="

    # deploy-instance.sh 실행 (실패해도 계속 진행)
    if "$DEPLOY_SCRIPT" "$INSTANCE" "$ZONE"; then
        DEPLOY_RESULTS["$INSTANCE"]="SUCCESS"
        print_success "${INSTANCE} 배포 성공"

        # 대기 시간
        WAIT_SEC=${WAIT_TIME[$INSTANCE]}
        print_info "${INSTANCE} 서비스 안정화 대기 중... (${WAIT_SEC}초)"
        sleep "$WAIT_SEC"
    else
        DEPLOY_RESULTS["$INSTANCE"]="FAILED"
        print_error "${INSTANCE} 배포 실패"
        print_warning "다음 인스턴스 배포를 계속합니다..."
    fi

    echo ""
done

# ===== 배포 결과 요약 =====
print_info "=========================================="
print_info "전체 배포 결과 요약"
print_info "=========================================="

SUCCESS_COUNT=0
FAILED_COUNT=0

for INSTANCE in "${INSTANCES[@]}"; do
    RESULT="${DEPLOY_RESULTS[$INSTANCE]}"
    if [ "$RESULT" = "SUCCESS" ]; then
        echo -e "${GREEN}✓${NC} ${INSTANCE}: ${GREEN}성공${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗${NC} ${INSTANCE}: ${RED}실패${NC}"
        ((FAILED_COUNT++))
    fi
done

echo ""
print_info "성공: ${SUCCESS_COUNT}개 / 실패: ${FAILED_COUNT}개"

# ===== 최종 상태 코드 반환 =====
if [ "$FAILED_COUNT" -gt 0 ]; then
    print_error "일부 인스턴스 배포 실패"
    exit 1
else
    print_success "=========================================="
    print_success "모든 인스턴스 배포 완료!"
    print_success "=========================================="
    print_info "서비스 상태 확인:"
    echo "  gcloud compute ssh speedcam-app --zone=${ZONE} --command='curl -s http://localhost/health'"
    echo "  gcloud compute ssh speedcam-mon --zone=${ZONE} --command='docker ps'"
    exit 0
fi
