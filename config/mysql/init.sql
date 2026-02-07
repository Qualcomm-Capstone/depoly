-- ===========================================
-- SpeedCam MSA 데이터베이스 초기화
-- ===========================================
-- MySQL 컨테이너 최초 실행 시 자동 실행

CREATE DATABASE IF NOT EXISTS speedcam_vehicles CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS speedcam_detections CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS speedcam_notifications CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER DATABASE speedcam CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

GRANT ALL PRIVILEGES ON speedcam_vehicles.* TO 'sa'@'%';
GRANT ALL PRIVILEGES ON speedcam_detections.* TO 'sa'@'%';
GRANT ALL PRIVILEGES ON speedcam_notifications.* TO 'sa'@'%';
FLUSH PRIVILEGES;
