data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------------------------------------
# IAM: SSM Session Manager for shell access (no SSH key, no port 22) plus
# read access to the one parameter holding the database URL.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name_prefix}-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "read_db_url" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.database_url.arn]
  }
}

resource "aws_iam_role_policy" "read_db_url" {
  name   = "read-database-url"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.read_db_url.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-app"
  role = aws_iam_role.app.name
}

# ---------------------------------------------------------------------------
# User data: a cloud-config that drops the bootstrap script, its settings
# and (for the default case) the demo app source onto disk, then runs the
# script. Settings are base64-encoded per key so arbitrary values survive
# without any shell quoting.
# ---------------------------------------------------------------------------

locals {
  use_demo_app = var.app_repo_url == ""

  demo_app_dir = "${path.module}/demo-app"
  demo_app_files = local.use_demo_app ? [
    for f in fileset(local.demo_app_dir, "**") : f
    if !startswith(f, "node_modules/") && !startswith(f, ".next/") && f != "package-lock.json"
  ] : []

  bootstrap_settings = {
    AWS_REGION      = var.region
    DB_URL_PARAM    = aws_ssm_parameter.database_url.name
    NODE_VERSION    = var.node_version
    APP_REPO_URL    = var.app_repo_url
    APP_GIT_REF     = var.app_git_ref
    APP_SUBDIR      = var.app_subdir
    APP_INSTALL_CMD = var.app_install_command
    APP_BUILD_CMD   = var.app_build_command
    APP_MIGRATE_CMD = var.app_migrate_command
    APP_START_CMD   = var.app_start_command
    APP_BACKEND_CMD = var.app_backend_start_command
    APP_PORT        = tostring(var.app_port)
    APP_EXTRA_ENV   = join("\n", [for k, v in var.app_extra_env : "${k}=${v}"])
  }

  user_data = "#cloud-config\n${yamlencode({
    write_files = concat(
      [
        {
          path        = "/etc/nextjs/bootstrap.conf"
          permissions = "0600"
          encoding    = "b64"
          content = base64encode(join("\n", [
            for k, v in local.bootstrap_settings : "${k}=${base64encode(v)}"
          ]))
        },
        {
          path        = "/opt/nextjs/bootstrap.sh"
          permissions = "0755"
          encoding    = "gz+b64"
          content     = base64gzip(file("${path.module}/scripts/bootstrap.sh"))
        },
      ],
      [
        for f in local.demo_app_files : {
          path        = "/opt/nextjs/demo-app/${f}"
          permissions = "0644"
          encoding    = "gz+b64"
          content     = base64gzip(file("${local.demo_app_dir}/${f}"))
        }
      ],
    )
    runcmd = [["/opt/nextjs/bootstrap.sh"]]
  })}"
}

# The instance launches in parallel with RDS (which takes ~5-8 minutes); the
# bootstrap script installs Node and fetches the app while it waits for the
# database URL parameter to appear.
resource "aws_instance" "app" {
  ami                  = data.aws_ssm_parameter.al2023_ami.value
  instance_type        = var.instance_type
  subnet_id            = aws_subnet.public[0].id
  iam_instance_profile = aws_iam_instance_profile.app.name

  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.name_prefix}-app" }

  lifecycle {
    # A new AL2023 release must not replace a running demo instance.
    ignore_changes = [ami]
  }
}

# ---------------------------------------------------------------------------
# Health check: keeps the apply (and so the Torque grain) running until the
# app answers, so an Active environment means the app actually serves
# traffic. The demo app's /api/health returns 503 until it can query RDS.
#
# Caveat: Terraform re-reads data sources on destroy. If the app is dead at
# teardown time the destroy will retry for health_check_timeout_minutes and
# fail; relaunch with wait_for_app=false or destroy with -refresh=false.
# ---------------------------------------------------------------------------

locals {
  health_check_path = var.health_check_path != "" ? var.health_check_path : (local.use_demo_app ? "/api/health" : "/")
  app_base_url      = var.app_port == 80 ? "http://${aws_instance.app.public_ip}" : "http://${aws_instance.app.public_ip}:${var.app_port}"
}

data "http" "app_health" {
  count = var.wait_for_app ? 1 : 0

  url                = "${local.app_base_url}${local.health_check_path}"
  request_timeout_ms = 5000

  retry {
    attempts     = var.health_check_timeout_minutes * 4
    min_delay_ms = 15000
    max_delay_ms = 15000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code >= 200 && self.status_code < 400
      error_message = "App at ${self.url} returned HTTP ${self.status_code}. Check /var/log/nextjs-bootstrap.log and 'journalctl -u nextjs' on the instance."
    }
  }

  depends_on = [aws_instance.app, aws_db_instance.this]
}

data "http" "extra_health" {
  for_each = var.wait_for_app ? { for c in var.extra_health_checks : "${c.port}${c.path}" => c } : {}

  url                = "http://${aws_instance.app.public_ip}:${each.value.port}${each.value.path}"
  request_timeout_ms = 5000

  retry {
    attempts     = var.health_check_timeout_minutes * 4
    min_delay_ms = 15000
    max_delay_ms = 15000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code >= 200 && self.status_code < 400
      error_message = "Endpoint ${self.url} returned HTTP ${self.status_code}. Check 'journalctl -u nextjs-backend' on the instance."
    }
  }

  depends_on = [aws_instance.app, aws_db_instance.this]
}
