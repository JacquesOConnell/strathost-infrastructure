# Plan 14: keep machine bootstrap non-secret and complete service setup separately through SSM.
module "ec2" {
  source                        = "./modules/ec2"
  environment                   = var.environment
  cost_center                   = var.cost_center
  public_subnet_ids             = module.networking.public_subnet_ids
  application_subnet_ids        = module.networking.application_subnet_ids
  docker_ami_id                 = var.docker_ami_id
  vpn_ami_id                    = var.vpn_ami_id
  checkmk_ami_id                = var.checkmk_ami_id
  docker_security_group_id      = module.security.security_group_ids.docker_hosts
  vpn_security_group_id         = module.security.security_group_ids.vpn_server
  checkmk_security_group_id     = module.security.security_group_ids.checkmk_server
  docker_instance_profile_name  = module.iam.instance_profile_names.docker
  vpn_instance_profile_name     = module.iam.instance_profile_names.vpn
  checkmk_instance_profile_name = module.iam.instance_profile_names.checkmk
  ebs_kms_key_arn               = module.encryption.key_arns.ebs
  protect_instances             = var.environment == "prod"
  bootstrap_user_data           = file("${path.module}/scripts/bootstrap/ssm.sh")
  # These module dependencies order service configuration, not invented readiness outputs.
  depends_on = [module.networking, module.security, module.storage, aws_iam_role_policy.docker_runtime, aws_iam_role_policy.vpn_runtime, aws_iam_role_policy.checkmk_artifacts]
}
