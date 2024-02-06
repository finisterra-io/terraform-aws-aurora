
locals {
  port = coalesce(var.port, (var.engine == "aurora-postgresql" || var.engine == "postgres" ? 5432 : 3306))

  is_serverless = var.engine_mode == "serverless"
}

################################################################################
# Cluster
################################################################################

resource "aws_rds_cluster" "this" {
  count = var.create ? 1 : 0

  allocated_storage                   = var.allocated_storage
  allow_major_version_upgrade         = var.allow_major_version_upgrade
  apply_immediately                   = var.apply_immediately
  availability_zones                  = var.availability_zones
  backup_retention_period             = var.backup_retention_period
  backtrack_window                    = var.backtrack_window
  cluster_identifier                  = var.cluster_identifier
  cluster_members                     = var.cluster_members
  copy_tags_to_snapshot               = var.copy_tags_to_snapshot
  database_name                       = var.database_name
  db_cluster_instance_class           = var.db_cluster_instance_class
  db_cluster_parameter_group_name     = var.db_cluster_parameter_group_name
  db_instance_parameter_group_name    = var.allow_major_version_upgrade ? var.db_cluster_db_instance_parameter_group_name : null
  db_subnet_group_name                = var.db_subnet_group_name
  deletion_protection                 = var.deletion_protection
  enable_global_write_forwarding      = var.enable_global_write_forwarding
  enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports
  enable_http_endpoint                = var.enable_http_endpoint
  engine                              = var.engine
  engine_mode                         = var.engine_mode
  engine_version                      = var.engine_version
  final_snapshot_identifier           = var.final_snapshot_identifier
  global_cluster_identifier           = var.global_cluster_identifier
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  iops                                = var.iops
  kms_key_id                          = var.kms_key_alias != null ? data.aws_kms_key.kms[0].arn : var.kms_key_id
  manage_master_user_password         = var.global_cluster_identifier == null && var.manage_master_user_password ? var.manage_master_user_password : null
  master_user_secret_kms_key_id       = var.global_cluster_identifier == null && var.manage_master_user_password ? var.master_user_secret_kms_key_id : null
  master_username                     = var.is_primary_cluster ? var.master_username : null
  network_type                        = var.network_type
  port                                = local.port
  preferred_backup_window             = local.is_serverless ? null : var.preferred_backup_window
  preferred_maintenance_window        = local.is_serverless ? null : var.preferred_maintenance_window
  replication_source_identifier       = var.replication_source_identifier

  dynamic "restore_to_point_in_time" {
    for_each = length(var.restore_to_point_in_time) > 0 ? [var.restore_to_point_in_time] : []

    content {
      restore_to_time            = try(restore_to_point_in_time.value.restore_to_time, null)
      restore_type               = try(restore_to_point_in_time.value.restore_type, null)
      source_cluster_identifier  = restore_to_point_in_time.value.source_cluster_identifier
      use_latest_restorable_time = try(restore_to_point_in_time.value.use_latest_restorable_time, null)
    }
  }

  dynamic "s3_import" {
    for_each = length(var.s3_import) > 0 && !local.is_serverless ? [var.s3_import] : []

    content {
      bucket_name           = s3_import.value.bucket_name
      bucket_prefix         = try(s3_import.value.bucket_prefix, null)
      ingestion_role        = s3_import.value.ingestion_role
      source_engine         = "mysql"
      source_engine_version = s3_import.value.source_engine_version
    }
  }

  dynamic "scaling_configuration" {
    for_each = length(var.scaling_configuration) > 0 && local.is_serverless ? [var.scaling_configuration] : []

    content {
      auto_pause               = try(scaling_configuration.value.auto_pause, null)
      max_capacity             = try(scaling_configuration.value.max_capacity, null)
      min_capacity             = try(scaling_configuration.value.min_capacity, null)
      seconds_until_auto_pause = try(scaling_configuration.value.seconds_until_auto_pause, null)
      timeout_action           = try(scaling_configuration.value.timeout_action, null)
    }
  }

  dynamic "serverlessv2_scaling_configuration" {
    for_each = length(var.serverlessv2_scaling_configuration) > 0 && var.engine_mode == "provisioned" ? [var.serverlessv2_scaling_configuration] : []

    content {
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
    }
  }

  skip_final_snapshot    = var.skip_final_snapshot
  snapshot_identifier    = var.snapshot_identifier
  source_region          = var.source_region
  storage_encrypted      = var.storage_encrypted
  storage_type           = var.storage_type
  tags                   = merge(var.tags, var.cluster_tags)
  vpc_security_group_ids = [for sg_id in var.vpc_security_group_ids : sg_id == "default" ? data.aws_security_group.default[0].id : sg_id]

  lifecycle {
    ignore_changes = [
      # See https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster#replication_source_identifier
      # Since this is used either in read-replica clusters or global clusters, this should be acceptable to specify
      replication_source_identifier,
      # See docs here https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_global_cluster#new-global-cluster-from-existing-db-cluster
      global_cluster_identifier,
      snapshot_identifier,
    ]
  }

}

################################################################################
# Cluster Instance(s)
################################################################################

resource "aws_rds_cluster_instance" "this" {
  for_each = { for k, v in var.instances : k => v if var.create && !local.is_serverless }

  apply_immediately                     = try(each.value.apply_immediately, var.apply_immediately)
  auto_minor_version_upgrade            = try(each.value.auto_minor_version_upgrade, var.auto_minor_version_upgrade)
  ca_cert_identifier                    = var.ca_cert_identifier
  cluster_identifier                    = aws_rds_cluster.this[0].cluster_identifier
  copy_tags_to_snapshot                 = try(each.value.copy_tags_to_snapshot, var.copy_tags_to_snapshot)
  db_parameter_group_name               = try(each.value.db_parameter_group_name, var.db_parameter_group_name)
  db_subnet_group_name                  = var.db_subnet_group_name
  engine                                = var.engine
  engine_version                        = var.engine_version
  identifier                            = var.instances_use_identifier_prefix ? null : try(each.value.identifier, "${var.name}-${each.key}")
  identifier_prefix                     = var.instances_use_identifier_prefix ? try(each.value.identifier_prefix, "${var.name}-${each.key}-") : null
  instance_class                        = try(each.value.instance_class, var.instance_class)
  monitoring_interval                   = try(each.value.monitoring_interval, var.monitoring_interval)
  monitoring_role_arn                   = try(each.value.monitoring_role_arn, var.monitoring_role_arn)
  performance_insights_enabled          = try(each.value.performance_insights_enabled, var.performance_insights_enabled)
  performance_insights_kms_key_id       = lookup(each.value, "performance_insights_kms_key_alias", null) != null ? data.aws_kms_key.performance_insights[each.key].arn : var.performance_insights_kms_key_id
  performance_insights_retention_period = try(each.value.performance_insights_retention_period, var.performance_insights_retention_period)
  preferred_maintenance_window          = try(each.value.preferred_maintenance_window, var.preferred_maintenance_window)
  promotion_tier                        = try(each.value.promotion_tier, null)
  publicly_accessible                   = try(each.value.publicly_accessible, var.publicly_accessible)
  tags                                  = try(each.value.tags, var.tags)

}

################################################################################
# Cluster Endpoint(s)
################################################################################

resource "aws_rds_cluster_endpoint" "this" {
  for_each = { for k, v in var.cluster_endpoint : k => v if var.create && !local.is_serverless }

  cluster_endpoint_identifier = each.key
  cluster_identifier          = var.cluster_identifier
  custom_endpoint_type        = each.value.type
  excluded_members            = try(each.value.excluded_members, null)
  static_members              = try(each.value.static_members, null)
  tags                        = try(each.value.tags, {})

  depends_on = [
    aws_rds_cluster_instance.this
  ]
}

################################################################################
# Cluster IAM Roles
################################################################################

resource "aws_rds_cluster_role_association" "this" {
  for_each = { for k, v in var.iam_roles : k => v if var.create }

  db_cluster_identifier = aws_rds_cluster.this[0].id
  feature_name          = each.value.feature_name
  role_arn              = each.value.role_arn
}


################################################################################
# Autoscaling
################################################################################

resource "aws_appautoscaling_target" "this" {
  count = var.create && var.autoscaling_enabled && !local.is_serverless ? 1 : 0

  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "cluster:${aws_rds_cluster.this[0].cluster_identifier}"
  scalable_dimension = var.scalable_dimension
  service_namespace  = var.service_namespace

  tags = var.appautoscaling_target_tags
}

resource "aws_appautoscaling_policy" "this" {
  count = var.create && var.autoscaling_enabled && !local.is_serverless ? 1 : 0

  name               = var.autoscaling_policy_name
  policy_type        = var.autoscaling_policy_type
  resource_id        = "cluster:${aws_rds_cluster.this[0].cluster_identifier}"
  scalable_dimension = var.scalable_dimension
  service_namespace  = var.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = var.predefined_metric_type
    }

    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
    target_value       = var.predefined_metric_type == "RDSReaderAverageCPUUtilization" ? var.autoscaling_target_cpu : var.autoscaling_target_connections
  }

  depends_on = [
    aws_appautoscaling_target.this
  ]
}
