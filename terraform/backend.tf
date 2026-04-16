terraform {
  backend "s3" {
    bucket         = "url-shortener-tf-state"
    key            = "env/${var.environment}/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
