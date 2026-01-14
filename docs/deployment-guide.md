# 배포 가이드라인 (Frontend/Backend 템플릿 사용법)

이 문서는 **현업/추후 프로젝트에서 재사용 가능한 배포 템플릿**으로 본 모니터링 스택을 사용하는 방법을 정리합니다. 모든 서비스는 동일한 Docker 네트워크(`monitor_net`)에서 통신하도록 구성되어 있으며, Prometheus가 Exporter 또는 `/metrics` 엔드포인트를 스크레이핑합니다.

## 1) 공통 준비 사항

1. `.env` 설정
   - `DB/mysql/.env.example`, `monitoring/.env.example`를 참고하여 `.env` 파일을 생성합니다.
2. 네트워크 생성
   - 모든 서비스는 `monitor_net` 네트워크에 연결되어야 합니다.
3. 모니터링 스택 실행
   ```bash
   ./start.sh
   ```

## 2) Backend 배포 템플릿

### 2-1. 서비스 컨테이너 구성 예시

아래 예시는 **Prometheus `/metrics` 엔드포인트를 노출하는 백엔드**를 대상으로 합니다. (예: Spring Actuator, Node.js `prom-client`, Go `promhttp` 등)

```yaml
version: "3.8"

services:
  api:
    image: your-org/your-backend:latest
    container_name: backend-api
    restart: always
    environment:
      APP_ENV: production
      METRICS_ENABLED: "true"
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    networks:
      - monitor_net

networks:
  monitor_net:
    external: true
```

### 2-2. Prometheus 스크레이핑 설정 추가

`monitoring/prometheus/prometheus.yml`에 백엔드 타겟을 추가합니다.

```yaml
scrape_configs:
  - job_name: 'backend'
    metrics_path: /metrics
    static_configs:
      - targets: ['backend-api:8080']
```

> **중요**: Prometheus가 접근할 수 있는 컨테이너 이름을 사용해야 합니다. 위 예시는 `backend-api` 컨테이너를 기준으로 합니다.

## 3) Frontend 배포 템플릿

프론트엔드는 정적 파일 서빙이 일반적이므로, **Nginx + nginx-prometheus-exporter** 형태로 모니터링 지표를 제공합니다.

```yaml
version: "3.8"

services:
  frontend:
    image: your-org/your-frontend:latest
    container_name: frontend-web
    restart: always
    ports:
      - "3000:80"
    networks:
      - monitor_net

  frontend-metrics:
    image: nginx/nginx-prometheus-exporter:1.3.0
    container_name: frontend-metrics
    command:
      - -nginx.scrape-uri=http://frontend:80/nginx_status
    depends_on:
      - frontend
    ports:
      - "9113:9113"
    networks:
      - monitor_net

networks:
  monitor_net:
    external: true
```

> `nginx_status`를 활성화하기 위해서는 Nginx 설정에 `stub_status`를 추가해야 합니다. (컨테이너 빌드 시 Nginx 설정에 반영)

### 3-1. Prometheus 스크레이핑 설정 추가

```yaml
scrape_configs:
  - job_name: 'frontend'
    static_configs:
      - targets: ['frontend-metrics:9113']
```

## 4) 배포 체크리스트 (실무 적용 기준)

- [ ] **환경변수/비밀키 분리**: `.env`에 민감 정보 저장, CI/CD에서는 Secret Manager 사용
- [ ] **헬스체크 추가**: `healthcheck` 정의 및 배포 파이프라인에서 검사
- [ ] **로그/트레이싱 연계**: 필요 시 Loki/Tempo 등과 연동
- [ ] **롤링 배포 전략**: 신규 배포 시 다운타임 방지
- [ ] **모니터링 지표 표준화**: `/metrics` 지표명, label 규칙 통일
- [ ] **대시보드 템플릿화**: 서비스별 Grafana 대시보드 공유 가능하게 관리

## 5) Grafana 접근 정보

- URL: http://localhost:13000
- 기본 계정: `.env`에서 `GF_SECURITY_ADMIN_USER`, `GF_SECURITY_ADMIN_PASSWORD` 설정
