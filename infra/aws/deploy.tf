# Shared deploy bucket (ADR 0024). A GitHub Actions run uploads each deploy
# bundle to deploy/<service>/<sha>/bundle.tar.gz and the on-box deploy script
# pulls it down. The name is built from the account id at plan time, the same
# pattern the state bucket uses (infra/bootstrap), so no literal account id ever
# lands in a committed file (invariant 7). This is NOT the state bucket: a CI
# role may write only its own deploy/<service>/ prefix here, and no role gets
# any access to state at all (F-001).
locals {
  deploy_bucket_name = "wkx-deploy-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "deploy" {
  bucket = local.deploy_bucket_name

  tags = { Name = local.deploy_bucket_name }
}

resource "aws_s3_bucket_versioning" "deploy" {
  bucket = aws_s3_bucket.deploy.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deploy" {
  bucket = aws_s3_bucket.deploy.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# 30-day expiry mirroring the ECR lifecycle: an old bundle is dead weight once
# its image has expired. Versioning is on, so noncurrent versions are swept on
# the same clock and incomplete multipart uploads are aborted.
resource "aws_s3_bucket_lifecycle_configuration" "deploy" {
  bucket = aws_s3_bucket.deploy.id

  rule {
    id     = "expire-bundles"
    status = "Enabled"

    filter {
      prefix = "deploy/"
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "deploy" {
  bucket                  = aws_s3_bucket.deploy.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "deploy_tls_only" {
  bucket = aws_s3_bucket.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.deploy.arn,
        "${aws_s3_bucket.deploy.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
