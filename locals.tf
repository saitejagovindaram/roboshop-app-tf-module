locals {
  # subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
  current_time = formatdate("DD-MM-YYYY-hh-mm", timestamp())
}

