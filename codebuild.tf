data "local_file" "docker_build_buildspec" {
  filename = "${path.module}/buildspecs/docker-build.yml"
}

resource "aws_codebuild_project" "build" {
  depends_on    = [aws_cloudwatch_log_group.account_provisioning_customizations]
  name          = "${var.environment_name}-${var.application_name}-build"
  description   = "Build docker for ${var.application_name}"
  build_timeout = var.build_configuration.build_timeout
  service_role  = aws_iam_role.build.arn
  tags          = local.tags

  artifacts {
    type                = "CODEPIPELINE"
    encryption_disabled = !var.build_configuration.encrypted_artifact
  }

  environment {
    compute_type                = var.build_configuration.compute_type
    image                       = var.build_configuration.image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
    dynamic "environment_variable" {
      for_each = local.build_envs
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.account_provisioning_customizations.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = local.build_spec
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.subnet_ids
    security_group_ids = [aws_security_group.builder.id]
  }
}

resource "aws_codebuild_project" "terraform_apply" {
  depends_on    = [aws_cloudwatch_log_group.account_provisioning_customizations]
  name          = "${var.environment_name}-${var.application_name}-terraform-apply"
  description   = "Apply Terraform"
  build_timeout = var.build_configuration.build_timeout
  service_role  = aws_iam_role.build.arn
  tags          = local.tags
  artifacts {
    type                = "CODEPIPELINE"
    encryption_disabled = !var.build_configuration.encrypted_artifact
  }

  environment {
    compute_type                = var.build_configuration.compute_type
    image                       = var.build_configuration.image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    dynamic "environment_variable" {
      for_each = local.build_envs
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.account_provisioning_customizations.name
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = templatefile("${path.module}/buildspecs/terraform-runner.yml", {
      TF_VERSION        = var.build_configuration.terraform_version
      TF_BACKEND_REGION = "eu-west-1"
      REGION            = "eu-west-1"
      TF_S3_BUCKET      = "terraform-state-${data.aws_caller_identity.current.account_id}"
      TF_S3_KEY         = "${var.environment_name}/${var.application_name}.tfstate"
      SERVICE           = var.application_name
      ENVIRONMENT       = var.environment_name
      TAGS              = jsonencode(var.tags)
      TARGETS = join(" ",[for t in var.resource_to_deploy: "-target=${t}"])
    })
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.subnet_ids
    security_group_ids = [aws_security_group.builder.id]
  }

}

resource "aws_security_group" "builder" {
  name        = "${var.environment_name}-${var.application_name}-CodeBuild"
  description = "test"
  vpc_id      = var.vpc_id
  egress = [
    {

      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]
  tags = merge(local.tags, {
    Name = "Build"
  })
}

resource "aws_cloudwatch_log_group" "account_provisioning_customizations" {
  name              = "/aws/codebuild/${var.environment_name}/${var.application_name}/build-logs"
  retention_in_days = var.logs_retention_in_days
  tags              = local.tags
}


