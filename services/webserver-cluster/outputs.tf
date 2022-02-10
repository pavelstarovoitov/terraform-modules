/*data "aws_instances" "example" {
  instance_tags = {
    Name = "terraform-asg-example"
  }
}

output "private-ips" {
  value = "${data.aws_instances.example.private_ips}"
}

output "public-ips" {
  value = "${data.aws_instances.example.public_ips}"
}*/

output "alb_dns_name" {
    value           = aws_lb.example.dns_name
    description     = "The domain name of the load balancer"
}

output "asg_name" {
  value     = aws_autoscaling_group.example.name 
  description = "The name of the Auto Scaling Group"
  
}