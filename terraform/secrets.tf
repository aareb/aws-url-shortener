resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/${var.env}/url-shortener/jwt-secret"
  type  = "SecureString"
  value = var.jwt_secret
}