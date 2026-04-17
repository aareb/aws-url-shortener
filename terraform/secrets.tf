resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/${var.env}/url-shortener/jwt-secret"
  type  = "SecureString"
  value = var.jwt_secret
}

resource "aws_ssm_parameter" "base_url" {
  name  = "/url-shortener/${var.env}/base_url"
  type  = "String"
  value = var.base_url
}