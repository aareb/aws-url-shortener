env         = "dev"
aws_region = "us-east-1"
base_url   = "https://dev.example.com"

resource "aws_s3_bucket" "waf_logs" {
  bucket = "url-shortener-waf-logs-dev"
}

module "waf" {
  source = "../../waf"

  name           = "url-shortener-dev"
  log_bucket_arn = aws_s3_bucket.waf_logs.arn
}