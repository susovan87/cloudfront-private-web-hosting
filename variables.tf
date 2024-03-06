variable "aws_account_id" {
  description = "The AWS account ID; default pointing to Dev to help with local debugging"
  type        = string
}

variable "aws_region" {
  description = "The AWS region; default pointing to eu-central-1 to help with local debugging"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "google_client_id" {
  description = "Google client ID"
  type        = string
}

variable "subdomain_name" {
  description = "Name of the subdomain to use for the CloudFront distribution"
  type        = string
}

variable "hosted_zone_name" {
  description = "Name of the Route53 hosted zone"
  type        = string
}

variable "max_session_duration" {
  description = "Maximum duration of the session in seconds; default is 8 hours"
  type        = number
  default     = 3600 * 8
}

variable "email_domain" {
  description = "Domain name for the email address (google workspace domain); leave empty to allow any google account"
  type        = string
  default     = ""
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
  }
}
