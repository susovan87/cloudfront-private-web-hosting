locals {
  cloudfront_domain = "${var.subdomain_name}.${data.aws_route53_zone.main.name}" # CloudFront domain name
  s3_origin_id      = "s3_oac_private_distribution"                              # Origin ID for the S3 bucket
  lambda_origin_id  = "lambda_oac_auth_signer"                                   # Origin ID for the lambda function
}



###  Data Sources    ###

# Origin request policy to forward all headers except host header
data "aws_cloudfront_origin_request_policy" "managed_all_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

# Cache policy to disable caching
data "aws_cloudfront_cache_policy" "managed_caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Cache policy to optimize caching
data "aws_cloudfront_cache_policy" "managed_caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Response headers policy to add CORS headers and security headers
data "aws_cloudfront_response_headers_policy" "managed_cors_preflight_security_headers" {
  name = "Managed-CORS-with-preflight-and-SecurityHeadersPolicy"
}

# Add record in Route 53 for the CloudFront distribution
data "aws_route53_zone" "main" {
  name = var.hosted_zone_name
}



###  Key pairs and key groups for signed cookies  ###

# Key pair for CloudFront; to generate the signatures for the signed cookies
resource "tls_private_key" "keypair" {
  algorithm = "RSA"
}

resource "aws_cloudfront_public_key" "cf_key" {
  encoded_key = tls_private_key.keypair.public_key_pem
}

resource "aws_cloudfront_key_group" "cf_keygroup" {
  items = [aws_cloudfront_public_key.cf_key.id]
  name  = "${var.subdomain_name}-keygroup"
}



###  Route 53 records and certificate    ###

# ACM certificate for the CloudFront distribution
module "acm" {
  providers = {
    aws = aws.us-east-1 # For CloudFront distribution, the certificate must be in us-east-1
  }

  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name = local.cloudfront_domain
  zone_id     = data.aws_route53_zone.main.zone_id

  wait_for_validation = true # Wait for the certificate to be validated before continuing
}

# Add record in Route 53 for the CloudFront distribution
resource "aws_route53_record" "a" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = local.cloudfront_domain
  type            = "A"
  allow_overwrite = true
  alias {
    name                   = aws_cloudfront_distribution.private.domain_name
    zone_id                = aws_cloudfront_distribution.private.hosted_zone_id
    evaluate_target_health = false
  }
}

# Add CAA record in Route 53 for the CloudFront distribution to allow only AWS to issue certificates
resource "aws_route53_record" "domain_caa" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.cloudfront_domain
  type    = "CAA"
  records = [
    "0 issue \"amazon.com\"",
    "0 issuewild \"amazon.com\"",
    "0 issue \"amazontrust.com\"",
    "0 issuewild \"amazontrust.com\"",
    "0 issue \"awstrust.com\"",
    "0 issuewild \"awstrust.com\"",
    "0 issue \"amazonaws.com\"",
    "0 issuewild \"amazonaws.com\""
  ]
  ttl = "1800"
}



###  CloudFront Distribution and Origin Access Control  ###

# Origin access control for the S3 bucket
resource "aws_cloudfront_origin_access_control" "default" {
  name                              = local.s3_origin_id
  description                       = "Example Policy"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution for the private content
resource "aws_cloudfront_distribution" "private" {
  enabled             = true
  comment             = "Some comment"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  wait_for_deployment = true # Wait for the distribution to be deployed before continuing

  aliases = [local.cloudfront_domain] # If you want to use a custom domain name

  # Origin for the S3 bucket
  origin {
    domain_name              = aws_s3_bucket.default.bucket_regional_domain_name # Regional domain name of the S3 bucket
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = local.s3_origin_id
  }

  # Default cache behavior to serve protected content from S3
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = local.s3_origin_id
    viewer_protocol_policy     = "redirect-to-https"                                                                    # Redirect HTTP to HTTPS
    compress                   = true                                                                                   # Compress the content before serving to save bandwidth
    trusted_key_groups         = [aws_cloudfront_key_group.cf_keygroup.id]                                              # Key group for the signed cookies
    cache_policy_id            = data.aws_cloudfront_cache_policy.managed_caching_optimized.id                          # Cache policy to optimize caching
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed_cors_preflight_security_headers.id # Response headers policy to add CORS headers and security headers
  }

  # Cache behavior with precedence 0; Serve the login page from S3
  # No truesed key group is set as the login page is public
  ordered_cache_behavior {
    path_pattern               = "/auth/login.html"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = local.s3_origin_id
    compress                   = true # Compress the content before serving to save bandwidth
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = data.aws_cloudfront_cache_policy.managed_caching_optimized.id                          # Cache policy to optimize caching
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.managed_cors_preflight_security_headers.id # Response headers policy to add CORS headers and security headers
  }

  # Origin for the lambda function URL; to validate user identity and return signed cookies
  origin {
    domain_name = replace(replace(module.lambda_function.lambda_function_url, "https://", ""), "/", "") # lambda function origin does not accept protocol and /
    origin_id   = local.lambda_origin_id
    custom_origin_config { # Custom origin configuration for the lambda function
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Cache behavior with precedence 1; Serve the lambda function for /auth/validate
  ordered_cache_behavior {
    path_pattern     = "/auth/validate"
    allowed_methods  = ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.lambda_origin_id

    viewer_protocol_policy = "https-only"
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.managed_caching_disabled.id                # Cache policy to disable caching
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.managed_all_except_host_header.id # Origin request policy to forward all headers except host header
  }

  # Geo restriction is disabled
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Viewer certificate for the CloudFront distribution
  viewer_certificate {
    ssl_support_method             = "sni-only"                     # Only SNI is supported
    minimum_protocol_version       = "TLSv1.2_2021"                 # Minimum TLS version recommended by AWS
    acm_certificate_arn            = module.acm.acm_certificate_arn # Custom certificate for the CloudFront distribution
    cloudfront_default_certificate = false
  }

  # Unauthenticated users are redirected to login page
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 403
    response_code         = 403
    response_page_path    = "/auth/login.html"
  }

  # redirect.html append index.html to the URL and redirect to the new URL if the file is not found
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 404
    response_page_path    = "/redirect.html"
  }
}
