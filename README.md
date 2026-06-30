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
              ├──▶ OIDC Provider (enables IRSA)
              │         │
              │         ▼
              └──▶ IAM Role ──▶ K8s ServiceAccount ──▶ Helm-installed
                                                        AWS Load Balancer
                                                        Controller
                          │
                          ▼
                 Helm install demo-app
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
   Deployment          Service            Ingress
   (2-6 pods,         (ClusterIP)     (real ALB, created
    HPA-scaled)                       automatically by
                                       the controller above)
```

## Tech Used

Terraform, Amazon EKS, Helm (both as CLI and as a Terraform provider), Kubernetes
(Deployment/Service/Ingress/HPA), AWS IAM (IRSA/OIDC), AWS Load Balancer Controller

## Usage

**Everything below is provisioned by a single `terraform apply`** — the EKS
cluster, the OIDC provider, the IAM role, and the AWS Load Balancer
Controller itself are all created in one pass. No manual `eksctl` or `helm
install` commands required.

```bash
cd terraform-eks-cluster
terraform init
terraform apply
aws eks update-kubeconfig --region ap-south-1 --name demo-eks-cluster

# confirm the controller came up automatically
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

**2. Deploy the app with Helm:**
```bash
cd ../helm-chart
helm install demo-release ./demo-app
kubectl get pods
kubectl get ingress -w   # wait ~1-2 min for a real ALB address to appear
```

**3. Verify the real ALB is live:**
```bash
curl -H "Host: demo-app.example.com" http://<alb-address-from-above>
```

**4. Verify autoscaling is wired up:**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get hpa
```

## Notes

This is a sanitized, standalone version of the cluster/Helm pattern I built
professionally, using a public demo image (`nginxdemos/hello`) instead of
real application code. In production, `image.repository` would point to a
private ECR repo built by the CI/CD pipeline (see the
`cicd-jenkins-github-actions` project).

The AWS Load Balancer Controller install is fully automated via Terraform's
`kubernetes` and `helm` providers (`lb-controller.tf`) — this demonstrates
IRSA (IAM Roles for Service Accounts), the modern pattern for giving
Kubernetes workloads scoped AWS permissions without static credentials.

## Cleanup

Order matters: delete the app's Ingress first so the controller deletes the
real ALB, **then** destroy the Terraform-managed infrastructure (which
includes uninstalling the controller itself).

```bash
helm uninstall demo-release          # deletes the Ingress -> controller removes the ALB
cd ../terraform-eks-cluster
terraform destroy
```
