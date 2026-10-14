terraform {
  backend "s3" {
    bucket       = "surf-school-terraform-state-636487155373"
    key          = "lab/terraform.tfstate"
    region       = "sa-east-1"
    profile      = "surf-school-lab"
    encrypt      = true
    use_lockfile = true
  }
}