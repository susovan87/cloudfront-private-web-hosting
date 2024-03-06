
# Create a S3 bucket to store the static files
resource "aws_s3_bucket" "default" {
  bucket = local.cloudfront_domain
}

# Set the bucket ACL to private
resource "aws_s3_bucket_acl" "default" {
  bucket = aws_s3_bucket.default.id
  acl    = "private"
}

# Set the bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "default" {
  bucket = aws_s3_bucket.default.id
  rule {
    object_ownership = "ObjectWriter"
  }
}

# Policy to allow the cloudfront distribution to access the files
data "aws_iam_policy_document" "default" {
  statement {
    sid    = "PolicyForCloudFrontPrivateContent"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["s3:GetObject", "s3:ListBucket"]

    resources = [
      "${aws_s3_bucket.default.arn}/*",
      aws_s3_bucket.default.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.private.arn]
    }
  }
}

# Apply the policy to allow the cloudfront distribution to access the files
resource "aws_s3_bucket_policy" "default" {
  bucket = aws_s3_bucket.default.id
  policy = data.aws_iam_policy_document.default.json
}

# Load the static files from the web-utils directory and apply template variables
module "static_files" {
  source  = "hashicorp/dir/template"
  version = "1.0.2"

  base_dir = "${path.module}/web-utils"
  template_vars = {
    google_client_id = var.google_client_id
    domain_name      = local.cloudfront_domain
  }
}

# Upload the static files to the S3 bucket
resource "aws_s3_object" "web_utils" {
  for_each = module.static_files.files

  bucket       = aws_s3_bucket.default.id
  key          = each.key == "login.html" ? "/auth/${each.key}" : each.key
  content_type = each.value.content_type
  source       = each.value.source_path
  content      = each.value.content
  etag         = each.value.digests.md5
}
