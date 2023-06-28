//terraform apply -var="lb_hostname=$(kubectl get services my-nginx-ingress-nginx-controller --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')" --auto-approve;
//terraform destroy -var="lb_hostname=$(kubectl get services my-nginx-ingress-controller --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')" --auto-approve;
provider "aws" {
  region = "us-east-1"
}

resource "aws_route53_zone" "selected" {
  name = "dev.andrewlklaas.com"
}

data "aws_elb_hosted_zone_id" "elb_zone_id" {}

resource "aws_route53_record" "my_record" {
  zone_id = aws_route53_zone.selected.zone_id
  name    = "dev.andrewlklaas.com"
  type    = "A"

  alias {
    name                   = var.lb_hostname
    zone_id                = data.aws_elb_hosted_zone_id.elb_zone_id.id
    evaluate_target_health = false
  }

  # records = [
  #   "ns-931.awsdns-52.net",
  #   "ns-178.awsdns-22.com",
  #   "ns-1157.awsdns-16.org",
  #   "ns-1711.awsdns-21.co.uk"
  # ]
}

resource "aws_route53_record" "dev-ns" {
  allow_overwrite = true
  zone_id = aws_route53_zone.selected.zone_id
  name    = "dev.andrewlklaas.com"
  type    = "NS"
  ttl     = "30"
  # records = [
  #   "ns-931.awsdns-52.net",
  #   "ns-178.awsdns-22.com",
  #   "ns-1157.awsdns-16.org",
  #   "ns-1711.awsdns-21.co.uk"
  # ]
    records = [
    "ns-1290.awsdns-33.org",
    "ns-1836.awsdns-37.co.uk",
    "ns-468.awsdns-58.com",
    "ns-631.awsdns-14.net"
  ]
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

output "name_servers" {
  value = aws_route53_zone.selected.name_servers
}