terraform {
  backend "s3" {
    bucket      = "url-shortener-tf-state"
    key         = "terraform.tfstate"
    region      = "ap-south-1"
    use_lockfile = true
    encrypt     = true
  }
}
