terraform {
  backend "s3" {
    bucket         = "myapp-terraform-state-mumbai"
    key            = "staging/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
