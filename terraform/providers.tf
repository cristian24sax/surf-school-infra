
terraform {
  required_version = ">= 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = "sa-east-1"
  profile = "surf-school-lab"

  allowed_account_ids = ["636487155373"]

  default_tags {
    tags = {
      Project     = "surf-school"
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }

}
