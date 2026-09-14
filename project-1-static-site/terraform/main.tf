# ============================================================
# PROJECT 1 — Terraform: S3 + CloudFront + ACM + Route 53
# ============================================================
# Services: S3, CloudFront, ACM, Route 53, IAM (OAC Policy)
# Region: us-east-1 (ACM for CloudFront MUST be us-east-1)
# ============================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state: S3 bucket + DynamoDB lock (create these manually first)
  # Uncomment after creating the state bucket
  # backend "s3" {
  #   bucket         = "aws-learning-tfstate-<your-account-id>"
  #   key            = "project-1/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "aws-learning-tf-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}

# ─────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region (must be us-east-1 for ACM + CloudFront)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier used in resource names"
  type        = string
  default     = "aws-learning-p1"
}

variable "domain_name" {
  description = "Your custom domain (e.g. mysite.example.com). Leave empty to skip Route 53 + ACM."
  type        = string
  default     = ""   # ← Set this to your domain if you have one
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

# ─────────────────────────────────────────────────────────────
# LOCAL VALUES
# ─────────────────────────────────────────────────────────────
locals {
  has_domain     = var.domain_name != ""
  bucket_name    = "${var.project_name}-site-${random_id.suffix.hex}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ─────────────────────────────────────────────────────────────
# 1. S3 BUCKET — Static Website Origin
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "site" {
  bucket        = local.bucket_name
}
