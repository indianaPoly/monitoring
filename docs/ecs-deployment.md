# AWS ECS(Fargate) + Terraform 배포 가이드

이 문서는 현재 로컬 Docker Compose 기반 모니터링 스택을 **실제 운영 환경(AWS ECS/Fargate)** 으로 배포할 수 있도록, **실행 순서와 아키텍처, Terraform 구성 포인트**를 단계별로 정리한 가이드입니다.

> 핵심 목표
> - 로컬 Compose → AWS ECS/Fargate로 전환
> - MySQL은 RDS로 대체(운영 권장)
> - Prometheus/Grafana는 ECS 서비스로 배포
> - 데이터 영속성을 위해 EFS 사용

---

## 1) 권장 아키텍처

```
[Client]
   │
   ▼
[ALB] ───────────────► [ECS Service: grafana]
   │
   └───────────────► [ECS Service: prometheus]

[RDS(MySQL)] ◄── [ECS Task: mysqld-exporter]
                    ▲
                    └── Prometheus가 exporter 스크레이핑

[EFS]
 ├─ /prometheus (Prometheus TSDB)
 └─ /grafana     (Grafana 설정/대시보드)
```

- **MySQL**: RDS 사용 권장 (운영 안정성/백업/모니터링 측면)
- **Prometheus/Grafana**: ECS(Fargate) 서비스
- **스토리지**: Prometheus/Grafana 데이터는 EFS로 영속화
- **접근**: ALB로 Grafana(13000) 및 Prometheus(19090) 노출

---

## 2) 준비 사항

1. **AWS 계정/권한**
2. **Terraform 설치**
3. **ECR 리포지토리 준비** (Grafana/Prometheus/Exporter 이미지)
4. **도메인/HTTPS 필요 시** ACM + Route53 준비

---

## 3) 단계별 배포 흐름 (요약)

1. **VPC/서브넷/보안그룹 구성**
2. **ECR 레포 생성 및 이미지 빌드/푸시**
3. **ECS 클러스터 + Task Definition 생성**
4. **EFS 생성 및 Task에 마운트**
5. **ALB + Target Group + Listener 연결**
6. **RDS 생성 및 exporter 설정**
7. **Prometheus scrape 설정 업데이트**

---

## 4) Terraform 구성 예시 (핵심 리소스)

> 아래 예시는 전체가 아닌 **핵심 구조**만 제공합니다. 실제 배포 시 모듈화 및 네이밍 정리가 필요합니다.

### 4-1. ECR

```hcl
resource "aws_ecr_repository" "prometheus" {
  name = "monitoring-prometheus"
}

resource "aws_ecr_repository" "grafana" {
  name = "monitoring-grafana"
}

resource "aws_ecr_repository" "mysqld_exporter" {
  name = "monitoring-mysqld-exporter"
}
```

### 4-2. ECS Cluster

```hcl
resource "aws_ecs_cluster" "monitoring" {
  name = "monitoring-cluster"
}
```

### 4-3. EFS (Prometheus/Grafana 데이터)

```hcl
resource "aws_efs_file_system" "monitoring" {
  creation_token = "monitoring-efs"
}
```

### 4-4. ECS Task Definition (Prometheus)

```hcl
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "prometheus"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "prometheus"
      image     = "${aws_ecr_repository.prometheus.repository_url}:latest"
      portMappings = [{ containerPort = 9090 }]
      mountPoints = [
        { sourceVolume = "prometheus-data", containerPath = "/prometheus" }
      ]
    }
  ])

  volume {
    name = "prometheus-data"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.monitoring.id
      root_directory = "/prometheus"
    }
  }
}
```

### 4-5. ECS Task Definition (Grafana)

```hcl
resource "aws_ecs_task_definition" "grafana" {
  family                   = "grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = "${aws_ecr_repository.grafana.repository_url}:latest"
      portMappings = [{ containerPort = 3000 }]
      mountPoints = [
        { sourceVolume = "grafana-data", containerPath = "/var/lib/grafana" }
      ]
    }
  ])

  volume {
    name = "grafana-data"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.monitoring.id
      root_directory = "/grafana"
    }
  }
}
```

### 4-6. RDS + mysqld-exporter

- 운영 환경에서는 **MySQL을 RDS로 대체**하는 것을 권장합니다.
- `mysqld-exporter`는 ECS Task로 실행하고 **RDS 접근용 유저**를 별도 생성합니다.

```hcl
# RDS는 별도 모듈 권장. 보안/백업/스냅샷 설정 포함.
```

Prometheus `prometheus.yml` 예시:

```yaml
scrape_configs:
  - job_name: 'mysqld'
    static_configs:
      - targets: ['mysqld-exporter:9104']
```

---

## 5) 이미지 빌드 & ECR 푸시 (예시)

```bash
# Prometheus
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com

docker build -t monitoring-prometheus ./monitoring

docker tag monitoring-prometheus:latest <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/monitoring-prometheus:latest

docker push <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/monitoring-prometheus:latest
```

Grafana / Exporter도 동일 패턴으로 빌드/푸시합니다.

---

## 6) 운영 환경 설정 체크리스트

- [ ] **비밀키/DB 비밀번호는 AWS Secrets Manager 사용**
- [ ] **보안그룹 최소화 (Prometheus/Grafana/Exporter 포트 제한)**
- [ ] **ALB 헬스체크 설정**
- [ ] **로그 수집: CloudWatch Logs 연동**
- [ ] **Grafana 기본 계정 변경 및 IAM 연동 고려**
- [ ] **백업 정책: EFS/RDS 스냅샷**

---

## 7) 대안: EC2 + Docker Compose

ECS가 부담스럽다면, 아래 대안도 가능합니다.

1. EC2 인스턴스 생성
2. Docker + Compose 설치
3. 기존 `start.sh` 실행
4. 보안그룹에 필요한 포트만 오픈

다만 **운영 안정성/오토스케일링/무중단 배포**를 생각하면 ECS(Fargate) 전환을 권장합니다.

---

## 8) 다음 단계 제안

원한다면 다음 작업도 확장 가능합니다:

- Terraform 모듈화 (VPC/RDS/ECS/ALB/EFS 분리)
- CI/CD (GitHub Actions → ECR → ECS 배포 파이프라인)
- Prometheus 알림 (Alertmanager) 구성
- Grafana SSO (SAML/OAuth)

---

필요하시면 **현재 레포 구조 기준으로 Terraform 전체 템플릿**을 더 구체적으로 만들어 드릴 수 있습니다.
