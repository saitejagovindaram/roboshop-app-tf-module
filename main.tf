/*  1. create instance
    2. provision with ansible or shell
    3. stop the instance 
    4. take AMI 
    5. delete instance
    6. create launch template with ami
    7. create Target group
    8. create auto scaling group
 */

# create instance
module "component" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  ami = var.ami_id
  name = "${var.project_name}-${var.component}-ami"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [var.component_sg_id]
  subnet_id              = element(var.private_subnet_ids, 0)
  iam_instance_profile = var.iam_instance_profile

  tags = merge(
    var.common_tags,
    {
        Name = "${var.component}"
    }
  )
}

# provision with ansible or shell
resource "null_resource" "component" {
  triggers = {
    instance_id = module.component.id
  }

  connection {
    host = module.component.private_ip
    type = "ssh"
    user = "centos"
    password = "DevOps321"
  }

  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} dev"
    ]
  }
}

#stop the instance
resource "aws_ec2_instance_state" "component" {
  instance_id = module.component.id
  state       = "stopped"
  depends_on = [ null_resource.component ]
}

# take AMI
resource "aws_ami_from_instance" "component" {
  name               = "${var.project_name}-${var.component}-ami-${local.current_time}"
  source_instance_id = module.component.id
  depends_on = [ aws_ec2_instance_state.component ]
}

# delete instance
resource "null_resource" "component_terminate" {
  
  triggers = {
    instance_id = aws_ami_from_instance.component.id
  }

  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${module.component.id}"
  }

  depends_on = [ aws_ami_from_instance.component ]
}

# create launch template with ami
resource "aws_launch_template" "component_template" {
    name = "${var.project_name}-${var.component}-template"

    image_id = aws_ami_from_instance.component.id
    instance_type = "t2.micro"
    vpc_security_group_ids = [var.component_sg_id] 
    instance_initiated_shutdown_behavior = "terminate" 

    tag_specifications {
    resource_type = "instance"

    tags = {
        Name = "${var.project_name}-${var.component}-${var.environment}"
      }
    }
}

# create Target group
resource "aws_lb_target_group" "component_tg" {
  name        = "${var.project_name}-${var.component}-tg"
  target_type = "instance" #default is instance
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  deregistration_delay = 60
  health_check {
    path = "/health"
    port = 8080
    healthy_threshold = 3
    interval = 10
    timeout = 5
    unhealthy_threshold = 2
    matcher =  "200-299"
  }
}

# create auto scaling group
resource "aws_autoscaling_group" "component_asg" {
  desired_capacity   = 2
  max_size           = 4
  min_size           = 1
  health_check_grace_period = 60
  health_check_type = "ELB"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns = [ aws_lb_target_group.component_tg.arn ]

  launch_template {
    id      = aws_launch_template.component_template.id
    version = aws_launch_template.component_template.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-${var.component}"
    propagate_at_launch = true
  }

}

# create autoscaling policy
resource "aws_autoscaling_policy" "component_targetTrackingPolicy" {
  name = "${var.project_name}-${var.environment}-asg_policy"
  autoscaling_group_name = aws_autoscaling_group.component_asg.name
  policy_type = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75
  }
}

# create load balancer listener rule
resource "aws_lb_listener_rule" "component_LBlistenerRule" {
  listener_arn = var.app_alb_listener_arn
  priority     = var.role_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.component_tg.arn
  }

  condition {
    host_header {
      values = ["${var.component}.app-alb-${var.environment}.saitejag.site"]
    }
  }
}