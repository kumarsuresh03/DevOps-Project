terraform {
  backend "s3" {
    bucket         = "myapp-terraform-state-mumbai"
    key            = "backend/prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
}
