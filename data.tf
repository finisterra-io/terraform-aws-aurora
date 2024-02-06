
data "aws_vpc" "default" {
  count = var.create && var.vpc_name != null ? 1 : 0
  tags = {
    Name = var.vpc_name
  }
}

data "aws_security_group" "default" {
  count  = var.create ? 1 : 0
  name   = "default"
  vpc_id = var.vpc_name != null ? data.aws_vpc.default[0].id : var.vpc_id
}

data "aws_kms_key" "kms" {
  count  = var.create && var.kms_key_alias != null ? 1 : 0
  key_id = var.kms_key_alias
}

data "aws_kms_key" "performance_insights" {
  for_each = var.create ? { for key, value in var.instances : key => value if lookup(value, "performance_insights_kms_key_alias", null) != null } : {}
  key_id   = each.value.performance_insights_kms_key_alias
}
