//terraform apply -var="lb_hostname=$(kubectl get services nginx-ingress-controller --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')" --auto-approve;
//terraform destroy -var="lb_hostname=$(kubectl get services nginx-ingress-controller --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')" --auto-approve;
provider "aws" {
  region = "us-east-1"
}

data "aws_route53_zone" "selected" {
  name         = "aklaas.sbx.hashidemos.io"
  private_zone = false
}
data "aws_elb_hosted_zone_id" "elb_zone_id" {}


resource "aws_route53_record" "my_record" {
  zone_id = data.aws_route53_zone.selected.zone_id 
  name    = "aklaas.sbx.hashidemos.io"
  type    = "A" 

  alias {
    name = var.lb_hostname
    zone_id = data.aws_elb_hosted_zone_id.elb_zone_id.id
    evaluate_target_health = false
  }
}

variable "lb_hostname" {
  type    = string
  default = ""
}
output "lb_hostname" {
  value = var.lb_hostname
}
output "aws_route53_record" {
  value = "http://${aws_route53_record.my_record.name}:80"
}
