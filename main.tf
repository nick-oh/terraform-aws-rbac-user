
# feature toggle
locals {
  login_on = lookup(var.features, "login", "off") == "on" ? true : false
}

# iam user module
resource "aws_iam_user" "user" {
  name          = var.name
  path          = "/"
  force_destroy = true

  tags = {
    Description = var.desc
  }
}

# security/policy
resource "aws_iam_user_policy_attachment" "policy" {
  count      = length(var.policy_arn)
  user       = aws_iam_user.user.name
  policy_arn = var.policy_arn[count.index]
}

# group membership
resource "aws_iam_user_group_membership" "groups" {
  user   = aws_iam_user.user.name
  groups = var.groups
}

# security/password
resource "random_password" "password" {
  count            = local.login_on == true ? 1 : 0
  length           = lookup(var.password_policy, "length", 16)
  number           = true
  special          = true
  override_special = "!@#$%^&*()_+-=[]{}|'"
}

# security/password suffix
resource "random_integer" "suffix" {
  count   = local.login_on == true ? 1 : 0
  min     = 1
  max     = 99
}

# login profile
data "template_file" "login-profile" {
  count    = local.login_on == true ? 1 : 0
  template = file(format("%s/resources/credential.tpl", path.module))

  vars = {
    name     = aws_iam_user.user.name
    password = format("%s%s", random_password.password[0].result, random_integer.suffix[0].result)
  }
}

locals {
  creds_filepath = format("%s/credentials/%s.json", path.cwd, aws_iam_user.user.name)
}

resource "local_file" "login-profile" {
  count             = local.login_on == true ? 1 : 0
  sensitive_content = data.template_file.login-profile[0].rendered
  filename          = local.creds_filepath
  file_permission   = "0600"
}

data "aws_region" "current" {}

resource "null_resource" "login-profile" {
  depends_on = [local_file.login-profile]
  count      = local.login_on == true ? 1 : 0
  provisioner "local-exec" {
    command = <<CLI
aws iam create-login-profile --cli-input-json file://${local.creds_filepath} --region ${data.aws_region.current.name}
CLI
  }
}
