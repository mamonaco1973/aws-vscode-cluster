# ================================================================================
# FILE: accounts.tf
# ================================================================================
#
# Purpose:
#   Generate strong random passwords for the Active Directory Administrator and
#   defined AD users. Store credentials securely in AWS Secrets Manager.
#
# Design:
#   - Passwords are generated at Terraform apply time.
#   - Credentials are stored as versioned secrets.
#   - No credentials are exposed via Terraform outputs.
#   - Secrets are permitted to be destroyed during environment teardown.
#
# Security Notes:
#   - Password length set to 24 characters to exceed AD complexity standards.
#   - Special characters enabled to increase entropy.
#   - Administrator override_special restricted for automation safety.
#   - User override_special allows broader complexity character set.
#
# ================================================================================


# ================================================================================
# SECTION: Active Directory Administrator Credential
# ================================================================================

# Generate a strong random password for the AD Administrator account.
resource "random_password" "admin_password" {
  length           = 24
  special          = true
  override_special = "_-."
}

# Create AWS Secrets Manager container for Administrator credentials.
resource "aws_secretsmanager_secret" "admin_secret" {
  name        = "admin_ad_credentials_rstudio"
  description = "Active Directory Administrator credentials"

  lifecycle {
    prevent_destroy = false
  }
}

# Store Administrator credentials as a versioned secret payload.
resource "aws_secretsmanager_secret_version" "admin_secret_version" {
  secret_id = aws_secretsmanager_secret.admin_secret.id

  secret_string = jsonencode({
    username = "${var.netbios}\\Admin"
    password = random_password.admin_password.result
  })
}


# ================================================================================
# SECTION: Active Directory User Credentials
# ================================================================================


# --------------------------------------------------------------------------------
# USER: John Smith (jsmith)
# --------------------------------------------------------------------------------

# Generate strong random password for user account.
resource "random_password" "jsmith_password" {
  length           = 24
  special          = true
  override_special = "!@#$%"
}

# Create Secrets Manager container for user credentials.
resource "aws_secretsmanager_secret" "jsmith_secret" {
  name        = "jsmith_ad_credentials_rstudio"
  description = "John Smith AD credentials"

  lifecycle {
    prevent_destroy = false
  }
}

# Store user credentials as a versioned secret payload.
resource "aws_secretsmanager_secret_version" "jsmith_secret_version" {
  secret_id = aws_secretsmanager_secret.jsmith_secret.id

  secret_string = jsonencode({
    username = "${var.netbios}\\jsmith"
    password = random_password.jsmith_password.result
  })
}


# --------------------------------------------------------------------------------
# USER: Emily Davis (edavis)
# --------------------------------------------------------------------------------

# Generate strong random password for user account.
resource "random_password" "edavis_password" {
  length           = 24
  special          = true
  override_special = "!@#$%"
}

# Create Secrets Manager container for user credentials.
resource "aws_secretsmanager_secret" "edavis_secret" {
  name        = "edavis_ad_credentials_rstudio"
  description = "Emily Davis AD credentials"

  lifecycle {
    prevent_destroy = false
  }
}

# Store user credentials as a versioned secret payload.
resource "aws_secretsmanager_secret_version" "edavis_secret_version" {
  secret_id = aws_secretsmanager_secret.edavis_secret.id

  secret_string = jsonencode({
    username = "${var.netbios}\\edavis"
    password = random_password.edavis_password.result
  })
}


# --------------------------------------------------------------------------------
# USER: Raj Patel (rpatel)
# --------------------------------------------------------------------------------

# Generate strong random password for user account.
resource "random_password" "rpatel_password" {
  length           = 24
  special          = true
  override_special = "!@#$%"
}

# Create Secrets Manager container for user credentials.
resource "aws_secretsmanager_secret" "rpatel_secret" {
  name        = "rpatel_ad_credentials_rstudio"
  description = "Raj Patel AD credentials"

  lifecycle {
    prevent_destroy = false
  }
}

# Store user credentials as a versioned secret payload.
resource "aws_secretsmanager_secret_version" "rpatel_secret_version" {
  secret_id = aws_secretsmanager_secret.rpatel_secret.id

  secret_string = jsonencode({
    username = "${var.netbios}\\rpatel"
    password = random_password.rpatel_password.result
  })
}


# --------------------------------------------------------------------------------
# USER: Amit Kumar (akumar)
# --------------------------------------------------------------------------------

# Generate strong random password for user account.
resource "random_password" "akumar_password" {
  length           = 24
  special          = true
  override_special = "!@#$%"
}

# Create Secrets Manager container for user credentials.
resource "aws_secretsmanager_secret" "akumar_secret" {
  name        = "akumar_ad_credentials_rstudio"
  description = "Amit Kumar AD credentials"

  lifecycle {
    prevent_destroy = false
  }
}

# Store user credentials as a versioned secret payload.
resource "aws_secretsmanager_secret_version" "akumar_secret_version" {
  secret_id = aws_secretsmanager_secret.akumar_secret.id

  secret_string = jsonencode({
    username = "${var.netbios}\\akumar"
    password = random_password.akumar_password.result
  })
}
