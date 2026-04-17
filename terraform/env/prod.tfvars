env         = "prod"
aws_region  = "us-east-2"
base_url    = "https://short.example.com"

resource "aws_s3_bucket" "waf_logs" {
  bucket = "url-shortener-waf-logs-prod"
}

module "waf" {
  source = "../../waf"

  name           = "url-shortener-prod"
  log_bucket_arn = aws_s3_bucket.waf_logs.arn
}
