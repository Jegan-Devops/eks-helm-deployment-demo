terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# These two data sources pull live connection info for the cluster we just
# created above, so the kubernetes/helm providers below can authenticate to
# it in the SAME apply — no separate "aws eks update-kubeconfig" step needed.
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate  = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                   = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate  = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    token                   = data.aws_eks_cluster_auth.main.token
  }
}
