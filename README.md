# EKS + Helm Deployment Demo

A complete pattern for provisioning an Amazon EKS cluster with Terraform and
deploying an application onto it with a reusable Helm chart — the same
combination I used in production to manage 50+ containerized applications
with zero-downtime deployments.

## Problem

Running containers in Kubernetes is one thing; running them on a *managed*,
production-grade EKS cluster with proper IAM separation, autoscaling, and
load-balancer integration is a different, more involved problem. Doing this
by hand in the console isn't repeatable or auditable.

## Solution

This repo splits the work into two reusable pieces:

1. **`terraform-eks-cluster/`** — provisions the EKS control plane, a managed
   node group, and the VPC/subnet/IAM scaffolding EKS needs, with subnets
   tagged so the AWS Load Balancer Controller can auto-discover them.
2. **`helm-chart/demo-app/`** — a parameterized Helm chart that deploys a
   sample app with readiness/liveness probes (for zero-downtime rolling
   updates), a Horizontal Pod Autoscaler, and an ALB Ingress.

## Architecture

```
Terraform ──▶ EKS Control Plane + Managed Node Group (2 AZs)
                          │
                          ▼
                 Helm install demo-app
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
   Deployment          Service            Ingress (ALB)
   (2-6 pods,         (ClusterIP)        internet-facing
    HPA-scaled)
```

## Tech Used

Terraform, Amazon EKS, Helm, Kubernetes (Deployment/Service/Ingress/HPA), AWS IAM, ALB

## Usage

**1. Provision the cluster:**
```bash
cd terraform-eks-cluster
terraform init
terraform apply
aws eks update-kubeconfig --region ap-south-1 --name demo-eks-cluster
```

**2. Deploy the app with Helm:**
```bash
cd ../helm-chart
helm install demo-release ./demo-app
kubectl get pods
kubectl get ingress
```

**3. Verify autoscaling is wired up:**
```bash
kubectl get hpa
```

## Notes

This is a sanitized, standalone version of the cluster/Helm pattern I built
professionally, using a public demo image (`nginxdemos/hello`) instead of
real application code. In production, `image.repository` would point to a
private ECR repo built by the CI/CD pipeline (see the
`cicd-jenkins-github-actions` project).

## Cleanup

```bash
helm uninstall demo-release
cd ../terraform-eks-cluster && terraform destroy
```
