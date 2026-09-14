#!/bin/bash
# ============================================================
# PROJECT 1 — CI/CD Setup Script
# Run karo: bash scripts/setup-cicd.sh
# Ye script:
#   1. IAM OIDC Provider banata hai (GitHub → AWS trust)
#   2. IAM Role banata hai (GitHub Actions assume karega)
#   3. Instructions deta hai GitHub Secrets ke liye
# ============================================================

set -e  # Koi bhi error aaye toh script rok do

# ─────────────────────────────────────────────
# COLORS for pretty output
# ─────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "=============================================="
echo "  PROJECT 1 — CI/CD Setup (OIDC + IAM Role)"
echo "=============================================="
echo -e "${NC}"

# ─────────────────────────────────────────────
# STEP 0: Inputs lo user se
# ─────────────────────────────────────────────
echo -e "${YELLOW}📝 Kuch details chahiye...${NC}"
echo ""

read -p "GitHub Username (e.g. shubhammittal): " GITHUB_USER
read -p "GitHub Repo Name (e.g. aws-learning): " GITHUB_REPO
read -p "S3 Bucket Name (terraform output se copy karo): " S3_BUCKET
read -p "CloudFront Distribution ID (terraform output se): " CF_DIST_ID
read -p "CloudFront Domain (e.g. dxxxx.cloudfront.net): " CF_DOMAIN

# AWS Account ID auto detect karo
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo ""
echo -e "${GREEN}✅ AWS Account ID: $ACCOUNT_ID${NC}"
echo ""

# ─────────────────────────────────────────────
# STEP 1: OIDC Provider banao
# GitHub Actions → AWS pe trust karne ke liye
# ─────────────────────────────────────────────
echo -e "${BLUE}🔐 STEP 1: IAM OIDC Provider check/create...${NC}"

# Check karo already exist karta hai kya
EXISTING=$(aws iam list-open-id-connect-providers \
  --query "OIDCProviderList[?ends_with(Arn, 'token.actions.githubusercontent.com')]" \
  --output text 2>/dev/null)

if [ -z "$EXISTING" ]; then
  echo "Creating OIDC Provider..."
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
  echo -e "${GREEN}✅ OIDC Provider created!${NC}"
else
  echo -e "${GREEN}✅ OIDC Provider already exists — skip!${NC}"
fi

OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

# ─────────────────────────────────────────────
# STEP 2: IAM Trust Policy banao
# "Sirf is GitHub repo se aane wale requests allow karo"
# ─────────────────────────────────────────────
echo ""
echo -e "${BLUE}📋 STEP 2: IAM Trust Policy bana raha hoon...${NC}"

cat > /tmp/github-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_USER}/${GITHUB_REPO}:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF

echo -e "${GREEN}✅ Trust policy ready!${NC}"

# ─────────────────────────────────────────────
# STEP 3: IAM Role banao
# ─────────────────────────────────────────────
echo ""
echo -e "${BLUE}👤 STEP 3: IAM Role bana raha hoon...${NC}"

ROLE_NAME="GitHubActions-P1-StaticSite-Deploy"

# Check karo already exist karta hai kya
ROLE_EXISTS=$(aws iam get-role --role-name $ROLE_NAME 2>/dev/null || echo "NOT_FOUND")

if echo "$ROLE_EXISTS" | grep -q "NOT_FOUND"; then
  aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file:///tmp/github-trust-policy.json \
    --description "GitHub Actions role for Project 1 static site deployment"
  echo -e "${GREEN}✅ IAM Role created: $ROLE_NAME${NC}"
else
  # Role exist karta hai — trust policy update karo
  aws iam update-assume-role-policy \
    --role-name $ROLE_NAME \
    --policy-document file:///tmp/github-trust-policy.json
  echo -e "${GREEN}✅ IAM Role already exists — trust policy updated!${NC}"
fi

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

# ─────────────────────────────────────────────
# STEP 4: IAM Policy banao (Least Privilege!)
# Sirf S3 + CloudFront pe specific permissions
# ─────────────────────────────────────────────
echo ""
echo -e "${BLUE}🛡️  STEP 4: IAM Permission Policy bana raha hoon...${NC}"

cat > /tmp/github-permissions.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3SyncAccess",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    },
    {
      "Sid": "CloudFrontInvalidation",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateInvalidation",
        "cloudfront:GetInvalidation",
        "cloudfront:ListInvalidations"
      ],
      "Resource": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CF_DIST_ID}"
    }
  ]
}
EOF

POLICY_NAME="GitHubActions-P1-Deploy-Policy"

# Check karo policy exist karta hai kya
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
POLICY_EXISTS=$(aws iam get-policy --policy-arn $POLICY_ARN 2>/dev/null || echo "NOT_FOUND")

if echo "$POLICY_EXISTS" | grep -q "NOT_FOUND"; then
  aws iam create-policy \
    --policy-name $POLICY_NAME \
    --policy-document file:///tmp/github-permissions.json \
    --description "Least privilege policy for GitHub Actions P1 deployment"
  echo -e "${GREEN}✅ IAM Policy created!${NC}"
else
  # New version create karo
  aws iam create-policy-version \
    --policy-arn $POLICY_ARN \
    --policy-document file:///tmp/github-permissions.json \
    --set-as-default
  echo -e "${GREEN}✅ IAM Policy updated!${NC}"
fi

# Policy Role se attach karo
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN 2>/dev/null || true

echo -e "${GREEN}✅ Policy attached to Role!${NC}"

# ─────────────────────────────────────────────
# STEP 5: Cleanup temp files
# ─────────────────────────────────────────────
rm -f /tmp/github-trust-policy.json /tmp/github-permissions.json

# ─────────────────────────────────────────────
# FINAL OUTPUT — GitHub Secrets ke liye
# ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}"
echo "=============================================="
echo "  ✅ SETUP COMPLETE!"
echo "=============================================="
echo -e "${NC}"
echo ""
echo -e "${YELLOW}📋 Ab GitHub Secrets add karo:${NC}"
echo ""
echo "  GitHub Repo → Settings → Secrets → Actions → New secret"
echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │ Secret Name              │ Value                        │"
echo "  ├─────────────────────────────────────────────────────────┤"
echo "  │ AWS_OIDC_ROLE_ARN        │ $ROLE_ARN │"
echo "  │ S3_BUCKET_NAME           │ $S3_BUCKET                   │"
echo "  │ CLOUDFRONT_DISTRIBUTION_ID│ $CF_DIST_ID                 │"
echo "  │ CLOUDFRONT_DOMAIN        │ $CF_DOMAIN                   │"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""
echo -e "${BLUE}🚀 Phir git push karo aur pipeline run hogi automatically!${NC}"
echo ""
