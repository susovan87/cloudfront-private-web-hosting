module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 4.0"

  # Basic Lambda Function Configuration
  function_name = "lambda-signer"
  description   = "Validate identity and return cloudfront signed cookie"
  handler       = "index.handler"
  runtime       = "nodejs18.x"

  # Environment Variables
  environment_variables = {
    CLOUDFRONT_DOMAIN              = local.cloudfront_domain
    CLOUDFRONT_KEYPAIR_ID          = aws_cloudfront_public_key.cf_key.id
    CLOUDFRONT_KEYPAIR_PRIVATE_KEY = base64encode(tls_private_key.keypair.private_key_pem) # base64encode is used to avoid error as private key contains new lines
    GOOGLE_CLIENT_ID               = var.google_client_id
    MAX_SESSION_DURATION           = var.max_session_duration
    EMAIL_DOMAIN                   = var.email_domain
  }

  # Lambda Package Configuration
  create_package = true
  source_path    = "${path.module}/signer-lambda"

  # Lambda Function URL Configuration
  create_lambda_function_url = true   # CloudFront supports lambda function URL as origin
  authorization_type         = "NONE" # No authorization required
  timeout                    = 5      # seconds

  # CORS Configuration
  cors = { # Enable CORS for the lambda function
    allow_credentials = true
    allow_origins     = ["https://${local.cloudfront_domain}"]
    allow_methods     = ["POST"]
    allow_headers     = ["*"]
  }
}