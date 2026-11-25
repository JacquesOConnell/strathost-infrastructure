# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 12; traceability A08.
# Use one Regional filesystem with three mount targets and separate site access points.

resource "aws_efs_file_system" "wordpress" {
  creation_token   = "${local.resource_prefix}-wordpress"
  encrypted        = true
  kms_key_id       = var.efs_kms_key_arn
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }
  tags = merge(local.tags, {
    Name         = "${local.resource_prefix}-efs-wordpress"
    BackupPolicy = "efs-daily"
  })
}

# ARCH / A08: three mount targets provide network access to one filesystem, not three copies of its data.
resource "aws_efs_mount_target" "wordpress" {
  for_each = var.application_subnet_ids

  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = each.value
  ip_address      = local.efs_mount_addresses[each.key]
  security_groups = [var.efs_security_group_id]
}

# DESIGN: stable POSIX IDs and per-site roots separate upload paths; the shared Docker role can mount all sites.
resource "aws_efs_access_point" "site" {
  for_each = var.site_posix_ids

  file_system_id = aws_efs_file_system.wordpress.id
  posix_user {
    uid = each.value
    gid = each.value
  }
  root_directory {
    path = "/sites/${each.key}"
    creation_info {
      owner_uid   = each.value
      owner_gid   = each.value
      permissions = "0750"
    }
  }
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-efs-ap-${each.key}"
    Site = each.key
  })
}

# DESIGN / plan 12 and 20: disable the duplicate automatic plan; the backup module explicitly selects this filesystem.
resource "aws_efs_backup_policy" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id
  backup_policy {
    status = "DISABLED"
  }
}

data "aws_iam_policy_document" "wordpress_filesystem" {
  statement {
    sid       = "DenyUnencryptedClientAccess"
    effect    = "Deny"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite", "elasticfilesystem:ClientRootAccess"]
    resources = [aws_efs_file_system.wordpress.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Deny NFS root privileges even if another identity policy grants them.
  statement {
    sid       = "DenyClientRootAccess"
    effect    = "Deny"
    actions   = ["elasticfilesystem:ClientRootAccess"]
    resources = [aws_efs_file_system.wordpress.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    sid       = "DenyUnexpectedClientRoles"
    effect    = "Deny"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.wordpress.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [var.docker_runtime_role_arn]
    }
  }

  statement {
    sid       = "DenyClientsWithoutApprovedAccessPoint"
    effect    = "Deny"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.wordpress.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [for access_point in aws_efs_access_point.site : access_point.arn]
    }
  }

  statement {
    sid       = "DenyClientsOutsideMountTargets"
    effect    = "Deny"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.wordpress.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "BoolIfExists"
      variable = "elasticfilesystem:AccessedViaMountTarget"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DockerMountAndWriteThroughSiteAccessPoints"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.wordpress.arn]
    principals {
      type        = "AWS"
      identifiers = [var.docker_runtime_role_arn]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["true"]
    }
    condition {
      test     = "Bool"
      variable = "elasticfilesystem:AccessedViaMountTarget"
      values   = ["true"]
    }
    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [for access_point in aws_efs_access_point.site : access_point.arn]
    }
  }
}

resource "aws_efs_file_system_policy" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id
  policy         = data.aws_iam_policy_document.wordpress_filesystem.json
}
