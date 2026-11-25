# Plan section 24: identifiers only; no key material.
output "key_arns" {
  description = "Key arns by purpose."
  value = {
    ebs     = aws_kms_key.ebs.arn
    rds     = aws_kms_key.rds.arn
    efs     = aws_kms_key.efs.arn
    backup  = aws_kms_key.backup.arn
    exports = aws_kms_key.exports.arn
    secrets = aws_kms_key.secrets.arn
    logs    = aws_kms_key.logs.arn
  }
}

output "key_ids" {
  description = "Key IDs by purpose."
  value = {
    ebs     = aws_kms_key.ebs.key_id
    rds     = aws_kms_key.rds.key_id
    efs     = aws_kms_key.efs.key_id
    backup  = aws_kms_key.backup.key_id
    exports = aws_kms_key.exports.key_id
    secrets = aws_kms_key.secrets.key_id
    logs    = aws_kms_key.logs.key_id
  }
}
