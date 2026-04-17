resource "aws_cognito_user_pool" "this" {
  name = "${var.env}-url-shortener-users"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.env}-url-shortener-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows  = ["implicit"]
  allowed_oauth_scopes = ["email", "openid"]
  callback_urls        = ["${var.base_url}/callback"]

  supported_identity_providers = ["COGNITO"]
}