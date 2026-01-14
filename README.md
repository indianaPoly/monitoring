# MySQL + phpMyAdmin + Prometheus + Grafana Docker Setup

This setup provides a modular Docker Compose architecture for running MySQL with persistent storage, a web interface via phpMyAdmin, and a monitoring stack using Prometheus and Grafana. It also includes a deployment guide for integrating frontend/backend services into the monitoring network.

---

## Folder Structure

```
DB/
└── mysql/
    ├── mysql_data/                # Persistent volume for MySQL data
    ├── mysqld-exporter/          # MySQL exporter config for Prometheus
    ├── scripts/
    │   └── ddl.sql                # Initial schema (optional)
    ├── docker-compose.yml        # MySQL and phpMyAdmin services

monitoring/
├── prometheus/
│   └── prometheus.yml            # Prometheus scrape configs
├── grafana/
│   └── provisioning/
│       ├── dashboards/
│       │   ├── dashboard.yml
│       │   └── mysql-overview.json
│       └── datasources/
│           └── datasource.yml
├── docker-compose.yml            # Prometheus + Grafana services
```

---

## Services

| Service           | Description                               | Port Mapping     |
|-------------------|-------------------------------------------|------------------|
| `mysql`           | MySQL 8.0 database server                 | `13306:3306`     |
| `phpmyadmin`      | Web UI for managing MySQL                | `18080:80`       |
| `mysqld-exporter` | Exposes MySQL metrics to Prometheus      | `19104:9104`     |
| `prometheus`      | Monitoring system to scrape exporters     | `19090:9090`     |
| `grafana`         | Visualization dashboard                   | `13000:3000`     |

---

## How to Use

### 1) 환경 변수 준비

- `DB/mysql/.env.example`, `monitoring/.env.example`를 참고하여 `.env` 파일을 생성합니다.

All services rely on a shared Docker network called `monitor_net`:

```bash
chmod +x ./start.sh
./start.sh
```

This folder contains MySQL's data files and persists across container restarts.

### 2) Frontend/Backend 템플릿 활용

현업 및 추후 프로젝트에서 재사용할 수 있는 배포 템플릿과 Prometheus 연동 방법은 아래 문서를 참고하세요.

- [배포 가이드라인 (Frontend/Backend 템플릿 사용법)](./docs/deployment-guide.md)
- [AWS ECS(Fargate) + Terraform 배포 가이드](./docs/ecs-deployment.md)

---

## Notes

- Access phpMyAdmin: [http://localhost:18080](http://localhost:18080)
- Access Prometheus: [http://localhost:19090](http://localhost:19090)
- Access Grafana: [http://localhost:13000](http://localhost:13000)

- All services must be connected to the `monitor_net` network for inter-container communication.

- Prometheus will automatically scrape metrics from:
  - `mysqld-exporter` (MySQL server metrics)
  - (Optional) `node-exporter` if added later

- Grafana dashboards and datasources are provisioned automatically at startup.
