data "aws_s3_bucket" "bucket_name" {
  bucket = var.pipeline_artifacts_bucket
}

resource "aws_iam_role" "codepipeline_role" {
  name = lower("${var.environment_name}-${var.application_name}-codepipeline-role")
  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        "Principal" : {
          "Service" : "codepipeline.amazonaws.com"
        },
        Action : "sts:AssumeRole"
      }
    ]
    }
  )
  tags = var.tags
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = lower("${var.environment_name}-${var.application_name}-codepipeline-policy")
  role = aws_iam_role.codepipeline_role.id
  policy = jsonencode(
    {
      Version : "2012-10-17",
      Statement : concat([
        {
          Effect : "Allow",
          Action : [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:GetBucketVersioning",
            "s3:List*",
            "s3:PutObjectAcl",
            "s3:PutObject"
          ],
          Resource : [
            data.aws_s3_bucket.bucket_name.arn,
            "${data.aws_s3_bucket.bucket_name.arn}/*"
          ]
        },
        {
          Effect : "Allow",
          Action : [
            "codebuild:BatchGetBuilds",
            "codebuild:StartBuild"
          ],
          Resource : "*"
        },
        {
          Effect : "Allow",
          Action : [
            "codecommit:GetBranch",
            "codecommit:GetRepository",
            "codecommit:GetCommit",
            "codecommit:GitPull",
            "codecommit:UploadArchive",
            "codecommit:GetUploadArchiveStatus",
            "codecommit:CancelUploadArchive"
          ],
          Resource : "arn:aws:codecommit:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        },
        {
          Effect : "Allow",
          Action : "codestar-connections:UseConnection",
          Resource : "*"
        },

        ],
        length(aws_codebuild_project.build) > 0 ? [{
          Effect : "Allow",
          Action : [
            "codebuild:StartBuild"
          ],
          Resource : [for build in aws_codebuild_project.build : "arn:aws:codebuild:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:project/${build.name}"]
      }] : [])
    }
  )
}


resource "aws_iam_role" "build" {
  name = lower("${var.environment_name}-${var.application_name}-codebuild-role")
  tags = var.tags
  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        "Principal" : {
          "Service" : "codebuild.amazonaws.com"
        },
        Action : "sts:AssumeRole"
      }
    ]
    }
  )
}

resource "aws_iam_role_policy" "codebuild_role" {
  name = lower("${var.environment_name}-${var.application_name}-codebuild-policy")
  role = aws_iam_role.build.id

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Resource : "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*",
        Action : [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs"
        ],
        Resource : "*"
      },
      {
        Effect : "Allow",
        Action : [
          "ec2:CreateNetworkInterfacePermission"
        ],
        Resource : [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:List*",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ],
        Resource : [
          data.aws_s3_bucket.bucket_name.arn,
          "${data.aws_s3_bucket.bucket_name.arn}/*",
          "arn:aws:s3:::${local.tf_state_bucket}/*"

        ]
      },
      #      {
      #        Effect : "Allow",
      #        Action : [
      #          "kms:Decrypt",
      #          "kms:Encrypt",
      #          "kms:GenerateDataKey"
      #        ],
      #        Resource : "${var.aft_key_arn}"
      #      },
      {
        Effect : "Allow",
        Action : [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ],
        Resource : [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/*"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "codecommit:GetBranch",
          "codecommit:GetRepository",
          "codecommit:GetCommit",
          "codecommit:GitPull",
          "codecommit:UploadArchive",
          "codecommit:GetUploadArchiveStatus",
          "codecommit:CancelUploadArchive"
        ],
        Resource : "arn:aws:codecommit:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect : "Allow",
        Action : [
          "sts:AssumeRole"
        ],
        Resource : local.roles_allowed_to_assume
      },
      {
        Effect : "Allow",
        Action : [
          "ecr:*"
        ],
        //TODO limit perms to single repo only
        Resource : [
          "*"
        ]
      }
    ]
    }
  )
}

locals {
  roles_allowed_to_assume = concat([
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSAFTAdmin"
  ], var.roles_allowed_to_assume)
}

variable "roles_allowed_to_assume" {
  type    = list(string)
  default = []
}
