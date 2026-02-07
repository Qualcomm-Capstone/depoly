#!/bin/bash
# ===========================================
# 환경 설정 자동 생성 스크립트
# ===========================================
# 사용법: ./scripts/setup-env.sh
# 사전 조건: env/hosts.env 파일 설정 완료

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# ===== hosts.env 로드 =====
HOSTS_ENV="${DEPLOY_DIR}/env/hosts.env"
if [ ! -f "$HOSTS_ENV" ]; then
    echo "[ERROR] ${HOSTS_ENV} 파일이 존재하지 않습니다."
    echo "  cp env/hosts.env.example env/hosts.env 후 설정하세요."
    exit 1
fi

source "$HOSTS_ENV"

echo "============================================="
echo " SpeedCam 환경 설정 생성"
echo "============================================="
echo " DB_HOST:    ${DB_HOST}"
echo " MQ_HOST:    ${MQ_HOST}"
echo " APP_HOST:   ${APP_HOST}"
echo " OCR_HOST:   ${OCR_HOST}"
echo " ALERT_HOST: ${ALERT_HOST}"
echo " MON_HOST:   ${MON_HOST}"
echo " DOMAIN:     ${DOMAIN:-없음 (IP 모드)}"
echo "============================================="
echo ""

# ===== 1. Traefik 동적 설정 =====
if [ -n "${DOMAIN:-}" ]; then
    echo "[1/3] Traefik 동적 설정 생성 (도메인 모드: ${DOMAIN})"

    # ACME 이메일 업데이트
    sed -i.bak "s/placeholder@example.com/${ACME_EMAIL}/" \
        "${DEPLOY_DIR}/config/traefik/traefik.yml" 2>/dev/null || \
    sed -i '' "s/placeholder@example.com/${ACME_EMAIL}/" \
        "${DEPLOY_DIR}/config/traefik/traefik.yml"
    rm -f "${DEPLOY_DIR}/config/traefik/traefik.yml.bak"

    envsubst '${DOMAIN} ${MON_HOST} ${MQ_HOST} ${TRAEFIK_AUTH_USER}' \
        < "${DEPLOY_DIR}/config/traefik/dynamic_conf.domain.yml.template" \
        > "${DEPLOY_DIR}/config/traefik/dynamic_conf.yml"
    echo "  → config/traefik/dynamic_conf.yml (도메인 모드)"
else
    echo "[1/3] Traefik 동적 설정 생성 (IP 모드)"
    cp "${DEPLOY_DIR}/config/traefik/dynamic_conf.ip.yml" \
       "${DEPLOY_DIR}/config/traefik/dynamic_conf.yml"
    echo "  → config/traefik/dynamic_conf.yml (IP 모드)"
fi

# ===== 2. Prometheus 설정 =====
echo "[2/3] Prometheus 설정 생성..."
envsubst '${DB_HOST} ${MQ_HOST} ${APP_HOST} ${OCR_HOST} ${ALERT_HOST}' \
    < "${DEPLOY_DIR}/config/monitoring/prometheus/prometheus.yml.template" \
    > "${DEPLOY_DIR}/config/monitoring/prometheus/prometheus.yml"
echo "  → config/monitoring/prometheus/prometheus.yml"

# ===== 3. Promtail 설정 =====
echo "[3/3] Promtail 설정 생성..."
envsubst '${MON_HOST}' \
    < "${DEPLOY_DIR}/config/monitoring/promtail/promtail-config.yml.template" \
    > "${DEPLOY_DIR}/config/monitoring/promtail/promtail-config.yml"
echo "  → config/monitoring/promtail/promtail-config.yml"

echo ""
echo "============================================="
echo " 완료!"
echo "============================================="
echo ""
echo " 아래 파일은 수동으로 설정하세요:"
echo "  - env/backend.env       (env/backend.env.example 참고)"
echo "  - env/mysql.env         (env/mysql.env.example 참고)"
echo "  - env/rabbitmq.env      (env/rabbitmq.env.example 참고)"
echo "  - config/monitoring/mysqld-exporter/.my.cnf"
echo ""
if [ -n "${DOMAIN:-}" ]; then
    echo " 도메인 DNS 설정:"
    echo "  A 레코드를 speedcam-app 외부 IP로 지정하세요:"
    echo "  - api.${DOMAIN}"
    echo "  - flower.${DOMAIN}"
    echo "  - grafana.${DOMAIN}"
    echo "  - rabbitmq.${DOMAIN}"
    echo "  - traefik.${DOMAIN}"
else
    echo " IP 모드로 설정됨:"
    echo "  - API 접근: http://<speedcam-app 외부IP>"
    echo "  - 관리 도구는 VPC 내부 IP로 직접 접근"
    echo "  - 도메인 추가 시: env/hosts.env에서 DOMAIN 설정 후 재실행"
fi
echo "============================================="
