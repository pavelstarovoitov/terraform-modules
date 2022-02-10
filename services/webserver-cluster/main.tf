# provider "aws" {
#     region = "us-east-2"
  
# }


terraform {
  backend "s3" {
      bucket            = "terraform-up-and-running-state-pavelstaravoitau1"
      key               = var.webserver_bucket_key
      region            = "us-east-2"

      dynamodb_table    = "terraform-up-and-running-locks"
      encrypt           = true
  }
}  

locals {
  http_port     = 80
  any_port      = 0
  any_protocol  = "-1"
  tcp_protocol  = "tcp"
  all_ips       = ["0.0.0.0/0"]
}

data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    bucket = var.db_remote_state_bucket
    key = var.db_remote_state_key
    region = "us-east-2"
  }
  
}

data "template_file" "user_data" {
  template = file("${path.module}/user-data.sh")

  vars = {
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
  }
}

resource "aws_launch_configuration" "example" {
  image_id = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type
  security_groups = [aws_security_group.instance.id]
  key_name = "${var.cluster_name}-deployer-key"

  user_data = data.template_file.user_data.rendered
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name
    vpc_zone_identifier = data.aws_subnet_ids.default.ids 

    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"

    min_size = var.min_size
    max_size = var.max_size

    tag {
        key         = "Name"
        value       = var.cluster_name
        propagate_at_launch = true 
    }
  
}

data "aws_vpc" "default"{
    default = true
}

data "aws_subnet_ids" "default"{
    vpc_id = data.aws_vpc.default.id 
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.cluster_name}-deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDx9c07Y4mpFFh18dPgBdDqm+lSuxjkPiNp8kAlC3Q80Nt4hUOKBHXZy9RjrQQVnsU7uh26TzqTBfJ8csP4wQU7iZhpID/mjbJu3WB303Hb7uU0S44zNhqYIk9jLrCMVjqGVyW0UUGtr844cZkwmqr0pbu+oR4wWhNGdMn3Ny+V/Vk428XlaseEje+R8CNSJy+T5k1MgA11gMjMT0VtGFf6o5uS0zRPML5giL9S/m79JgnWJtfmw7EoL3zkm/rpif0LKepfehi9qGQnH13WJoQYLly6tw9LhFzWJsZg4oQdBfAOQDKUDTZhR1dpL9My8OPfwZuSpqc9WVh3zAoh7S0SnxfDlDGIKhU6OOHGXiv10O8GG6KQaCmSl0xhk/MrzsDpN2vz7VyGiLATE3ZfbKnK0cZhRkX9qBaStYeJpP7C04V5BX0sfmGPpjWmLrAesJTUmSE2iZU7EwISl9cnMTKIb3Xu67SJngczaFtnu/OoFGlgVF4x0JO77CKWtnuNETU= starik@starik-thinkpad"
}
resource "aws_security_group" "instance" {
    name = "${var.cluster_name}-instance"
}

resource "aws_security_group_rule" "allow-8080" {
  type = "ingress"
  security_group_id = aws_security_group.instance.id

  ipv6_cidr_blocks = ["::/0"]
  prefix_list_ids = []
  cidr_blocks = local.all_ips
  description = "terraform example"
  from_port = var.server_port
  protocol = "tcp"
  to_port = var.server_port   
}

resource "aws_security_group_rule" "allow-ssh" {
  type = "ingress"
  security_group_id = aws_security_group.instance.id

  ipv6_cidr_blocks = []
  prefix_list_ids = []
  cidr_blocks = local.all_ips
  description = "terraform example"
  from_port = 22
  protocol = "tcp"
  to_port = 22
}

resource "aws_security_group_rule" "allow-icmp" {
  type = "ingress"
  security_group_id = aws_security_group.instance.id

  ipv6_cidr_blocks = []
  prefix_list_ids = []
  cidr_blocks = local.all_ips
  description = "terraform example"
  from_port = -1
  protocol = "icmp"
  to_port = -1
}

resource "aws_security_group_rule" "allow-http-80" {
  type = "ingress"
  security_group_id = aws_security_group.instance.id

  ipv6_cidr_blocks = []
  prefix_list_ids = []
  cidr_blocks = local.all_ips
  description = "terraform example"
  from_port = local.http_port
  protocol = local.tcp_protocol
  to_port = local.http_port
}
  
resource "aws_security_group_rule" "allow-egress" {
  type = "egress"
  security_group_id = aws_security_group.instance.id
    
  from_port        = local.any_port
  to_port          = local.any_port
  protocol         = local.any_protocol
  cidr_blocks      = local.all_ips
  ipv6_cidr_blocks = ["::/0"]
}

resource "aws_lb" "example" {
    name                    = "${var.cluster_name}-lb-example"
    load_balancer_type      = "application"
    subnets                 = data.aws_subnet_ids.default.ids 
    security_groups         = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example.arn 
    port              = local.http_port
    protocol          = "HTTP"
    default_action {
      type = "fixed-response"

      fixed_response {
          content_type = "text/plain"
          message_body = "404: page not found"
          status_code  = 404
      }
    }
}

resource "aws_security_group" "alb" {
    name = "${var.cluster_name}-alb"
}
resource "aws_security_group_rule" "allow_http_inbound" {
    type = "ingress" 
    security_group_id = aws_security_group.alb.id

    ipv6_cidr_blocks = []
    prefix_list_ids = []
    cidr_blocks = local.all_ips
    description = "alb ingress"
    from_port = local.http_port
    protocol = local.tcp_protocol
    to_port = local.http_port
}
resource "aws_security_group_rule" "allow_all_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb.id

  cidr_blocks = local.all_ips
  description = "alb egress"
  from_port = local.any_port
  ipv6_cidr_blocks = []
  prefix_list_ids = []
  protocol = local.any_protocol
  to_port = local.any_port
}
    
  
resource "aws_lb_target_group" "asg" {
 name           = "${var.cluster_name}-asg-example"
 port           = var.server_port
 protocol       = "HTTP"
 vpc_id         = data.aws_vpc.default.id

 health_check {
     path       = "/"
     protocol   = "HTTP"
     matcher    = "200"
     interval   = 15
     timeout    = 3
     healthy_threshold   = 2
     unhealthy_threshold = 2  
 }
}

resource "aws_lb_listener_rule" "asg" {
    listener_arn = aws_lb_listener.http.arn 
    priority     = 100

    condition {
        path_pattern {
            values = ["*"]
        }
    }
    action {
        type                    = "forward"
        target_group_arn   = aws_lb_target_group.asg.arn
    }
}
  