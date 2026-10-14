
data "aws_vpc" "surf_school" {
  id = "vpc-06210c3c1ffff6868"
}

data "aws_subnet" "app_1" {
  id = "subnet-09db1465fe7e8735b"
}

data "aws_subnet" "app_2" {
  id = "subnet-07a65d8609ea80a53"
}

data "aws_security_group" "endpoints" {
  id = "sg-03f5c7d9aa00c3501"
}
