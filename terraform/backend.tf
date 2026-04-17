terraform {
  backend "s3" {
    bucket      = "url-shortener-tf-state-new"
    key         = "terraform.tfstate"
    region      = "eu-west-2"
    use_lockfile = true
    encrypt     = true
  }
}
