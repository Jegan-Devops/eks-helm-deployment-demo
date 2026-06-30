# ---------------------------------------------------------------------------
# This file fully automates what would otherwise be manual steps:
#   1. Register an OIDC identity provider for the cluster (lets Kubernetes
#      service accounts assume IAM roles — "IRSA")
#   2. Create the IAM policy + role the controller needs (least-privilege,
#      scoped to ALB/NLB management actions)
#   3. Install the AWS Load Balancer Controller via the Helm provider
#
# Running `terraform apply` once now provisions the cluster AND a working
# ALB controller — no eksctl, no manual `helm install` afterward.
# ---------------------------------------------------------------------------

# Step 1: OIDC provider — required for IRSA to work at all
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}

# Step 2: Pull the official AWS-published IAM policy directly from GitHub at
# apply time, instead of pasting a 16KB JSON blob into this repo — this also
# means it always matches the controller version actually being installed.
data "http" "lb_controller_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.9.0/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "lb_controller" {
  name   = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.lb_controller_iam_policy.response_body
}

# The trust policy here is the actual IRSA magic: it only allows this exact
# Kubernetes service account (namespace + name) in THIS cluster's OIDC
# provider to assume the role — not any pod, not any cluster.
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "lb_controller" {
  name = "${var.cluster_name}-lb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# Step 3: the Kubernetes-side service account, annotated to point at the IAM
# role above — this annotation is what actually links a pod to AWS permissions.
resource "kubernetes_service_account" "lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.lb_controller.arn
    }
    labels = {
      "app.kubernetes.io/component" = "controller"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# Step 4: install the controller itself
resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = aws_vpc.eks_vpc.id
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lb_controller.metadata[0].name
  }

  depends_on = [
    kubernetes_service_account.lb_controller,
    aws_iam_role_policy_attachment.lb_controller,
  ]
}
