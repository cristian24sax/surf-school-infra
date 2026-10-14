
locals {
  interface_endpoints = {
    ecr_api = {
      service = "ecr.api"
      name    = "surf-school-ecr-api-endpoint"
    }

    ecr_dkr = {
      service = "ecr.dkr"
      name    = "surf-school-ecr-dkr-endpoint"
    }

    logs = {
      service = "logs"
      name    = "surf-school-cloudwatch-logs-endpoint"
    }

    secretsmanager = {
      service = "secretsmanager"
      name    = "surf-school-secretsmanager-endpoint"
    }
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.lab_enabled ? local.interface_endpoints : {}

  vpc_id = data.aws_vpc.surf_school.id

  service_name = "com.amazonaws.sa-east-1.${each.value.service}"

  vpc_endpoint_type = "Interface"

  private_dns_enabled = true

  subnet_ids = [
    data.aws_subnet.app_1.id,
    data.aws_subnet.app_2.id
  ]

  security_group_ids = [
    data.aws_security_group.endpoints.id
  ]

  tags = {
    Name      = each.value.name
    ManagedBy = "manual"
  }
  #   lifecycle {
  #     prevent_destroy = true
  #   }
}
