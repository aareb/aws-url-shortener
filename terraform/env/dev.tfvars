env            = "dev"
aws_region     = "us-east-1"
base_url       = "https://dev.example.com"
environment    = "dev"
project_name   = "url-shortener"
log_bucket_arn = "arn:aws:s3:::url-shortener-waf-logs-dev"
jwt_secret     = "your-jwt-secret-here"

  name           = "url-shortener-dev"
  log_bucket_arn = aws_s3_bucket.waf_logs.arn
}