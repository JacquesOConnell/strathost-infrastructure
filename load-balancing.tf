module "load_balancing" {
  source                         = "./modules/load-balancing"
  environment                    = var.environment
  cost_center                    = var.cost_center
  vpc_id                         = module.networking.vpc_id
  public_subnet_ids              = module.networking.public_subnet_ids
  application_subnet_ids         = module.networking.application_subnet_ids
  public_alb_security_group_id   = module.security.security_group_ids.public_alb
  secure_alb_security_group_id   = module.security.security_group_ids.secure_alb
  internal_alb_security_group_id = module.security.security_group_ids.internal_alb
  docker_instance_ids            = module.ec2.docker_instance_ids
  access_logs_bucket_name        = module.storage.bucket_names.alb_access_logs
  certificate_arns               = var.certificate_arns
  hostnames                      = var.hostnames
  enable_public_routing          = var.enable_public_routing
  enable_internal_routing        = var.enable_internal_routing
  enable_secure_routing          = var.enable_secure_routing
  secure_origin_auth_verified    = var.secure_origin_auth_verified
  depends_on                     = [module.storage, module.security]
}
