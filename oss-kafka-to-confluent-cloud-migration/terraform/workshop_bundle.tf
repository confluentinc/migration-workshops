# The bastion's copy of the workshop scripts (clients/, gateway/, kcp/, cleanup.sh) comes
# from the checkout you run terraform in, so it always matches what you're deploying and
# doesn't depend on what's published on GitHub.
data "archive_file" "workshop" {
  type        = "zip"
  source_dir  = "${path.module}/.."
  output_path = "${path.module}/.terraform/workshop-bundle.zip"
  excludes = [
    "terraform/**", "assets/**", "STEP-*/**", "*.md", ".gitignore",
    "**/.venv/**", "**/__pycache__/**", "**/.DS_Store", "clients/logs/**", "**/*.pid",
    "gateway/rendered-crs/**", "target_infra/**", "migration-infra/**", "migrate_topics/**",
    "kcp-state.json", "kcp.log", "migration-state.json", "metric_report_*.md",
    "workshop.env", "target.env", "ca.pem",
  ]
}

resource "aws_s3_bucket" "workshop" {
  bucket_prefix = "${var.name_prefix}-workshop-"
  force_destroy = true
}

resource "aws_s3_object" "workshop" {
  bucket      = aws_s3_bucket.workshop.id
  key         = "workshop.zip"
  source      = data.archive_file.workshop.output_path
  source_hash = data.archive_file.workshop.output_base64sha256
}

# Readable only through the VPC's S3 endpoint, so the bastion needs no AWS credentials to
# fetch it and nothing outside the VPC can. (S3 doesn't treat a policy scoped to
# aws:SourceVpce as public, so the bucket's default Block Public Access still applies.)
resource "aws_s3_bucket_policy" "workshop" {
  bucket = aws_s3_bucket.workshop.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ReadFromWorkshopVpcOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.workshop.arn}/*"
      Condition = {
        StringEquals = { "aws:SourceVpce" = aws_vpc_endpoint.s3.id }
      }
    }]
  })
}
