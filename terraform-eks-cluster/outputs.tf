output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "configure_kubectl" {
  description = "Run this command to point kubectl at the new cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "lb_controller_status" {
  description = "Confirms the AWS Load Balancer Controller Helm release that was auto-installed"
  value       = "aws-load-balancer-controller installed in kube-system — check with: kubectl get pods -n kube-system | grep aws-load-balancer-controller"
}
