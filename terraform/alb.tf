
# ALB existente de Surf School
resource "aws_lb" "surf_school" {
  name               = "surf-school-alb"
  internal           = false
  load_balancer_type = "application"
  count              = var.lab_enabled ? 1 : 0
  security_groups = [
    "sg-011d057394ec79b95"
  ]

  subnets = [
    "subnet-02f02ea855366bc67",
    "subnet-092a63b00f3952696"
  ]

  ip_address_type = "ipv4"

  tags = {
    Name = "surf-school-alb"
  }

  #   lifecycle {
  #     prevent_destroy = true
  #   }
}

# Consultamos el Target Group existente
# Sin asumir todavía su administración por Terraform
data "aws_lb_target_group" "api" {
  name = "surf-school-api-tg"
}

# Listener HTTP existente

resource "aws_lb_listener" "http" {
  count             = var.lab_enabled ? 1 : 0
  load_balancer_arn = aws_lb.surf_school[0].arn

  port     = 80
  protocol = "HTTP"


  default_action {
    type  = "forward"
    order = 1

    target_group_arn = data.aws_lb_target_group.api.arn

    forward {
      target_group {
        arn    = data.aws_lb_target_group.api.arn
        weight = 1
      }

      stickiness {
        enabled  = false
        duration = 3600
      }
    }
  }


  #   lifecycle {
  #     prevent_destroy = true
  #   }
}

