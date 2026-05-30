# Infraestrutura como Código (IaC)

Manifests Kubernetes para deploy do monorepo Rails Patterns.

## Estrutura

```
iac/
├── k8s/
│   ├── namespace.yaml
│   ├── core-db.yaml          # PostgreSQL do core
│   ├── consumer-db.yaml      # PostgreSQL do consumer (isolado)
│   ├── redis.yaml
│   ├── core.yaml             # API Rails
│   ├── consumer.yaml         # Karafka consumer
│   ├── sidekiq.yaml
│   ├── frontend.yaml
│   └── ingress.yaml
└── README.md
```

## Pré-requisitos

- Cluster Kubernetes (minikube, kind, EKS, GKE)
- `kubectl` configurado
- Kafka externo ou operador Strimzi (não incluído — use docker-compose local)

## Deploy local (kind/minikube)

```bash
kubectl apply -f iac/k8s/namespace.yaml
kubectl apply -f iac/k8s/core-db.yaml
kubectl apply -f iac/k8s/consumer-db.yaml
kubectl apply -f iac/k8s/redis.yaml
kubectl apply -f iac/k8s/core.yaml
kubectl apply -f iac/k8s/consumer.yaml
kubectl apply -f iac/k8s/sidekiq.yaml
kubectl apply -f iac/k8s/frontend.yaml
kubectl apply -f iac/k8s/ingress.yaml
```

## Variáveis de ambiente críticas

| Serviço | Variável | Descrição |
|---------|----------|-----------|
| core | `DATABASE_URL` | Postgres do core |
| core | `JWT_SECRET` | Secret para tokens |
| core | `REDIS_URL` | Sidekiq + cache |
| core | `KAFKA_URL` | Broker Kafka |
| consumer | `CONSUMER_DATABASE_URL` | Postgres **separado** |
| consumer | `KAFKA_URL` | Broker Kafka |

## Notas

- DBs do core e consumer são **Deployments separados** — nunca compartilham volume.
- Em produção, substitua Postgres in-cluster por RDS/Cloud SQL gerenciado.
- Imagens Docker devem ser publicadas no registry antes do deploy (`make build` + push).
