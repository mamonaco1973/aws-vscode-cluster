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
#   - Administrator: a strong 24-character random password, used by
#     automation for the domain join and never typed.
#   - Users: friendly "<word>-<number>" passwords (e.g. orange-481920) so
#     they are easy to type at the VS Code / desktop login during a demo.
#     lower + digit + "-" satisfies AD's 3-of-4 complexity rule, and the
#     leading word means samba-tool never mistakes one for an option.
#
# ================================================================================


# ================================================================================
# SECTION: Active Directory Administrator Credential
# ================================================================================

# Generate a strong random password for the AD Administrator account.
resource "random_password" "admin_password" {
  length           = 24
  special          = true
  override_special = "_."

  # AD requires 3 of 4 character classes. With only two symbols allowed, a
  # 24-character draw can easily contain no symbol (and no digit) at all, so
  # every class is guaranteed rather than left to chance.
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

# Create AWS Secrets Manager container for Administrator credentials.
resource "aws_secretsmanager_secret" "admin_secret" {
  name        = "admin_ad_credentials_vscode"
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
# Friendly User Passwords: "<word>-<number>"
# --------------------------------------------------------------------------------

locals {
  word_users = toset(["jsmith", "edavis", "rpatel", "akumar"])

  memorable_words = [
    "bright", "simple", "orange", "window", "little", "people", "friend",
    "yellow", "animal", "family", "circle", "moment", "summer", "button",
    "planet", "rocket", "silver", "forest", "stream", "butter", "castle",
    "wonder", "gentle", "driver", "coffee"
  ]
}

resource "random_shuffle" "word" {
  for_each     = local.word_users
  input        = local.memorable_words
  result_count = 1
}

resource "random_integer" "num" {
  for_each = local.word_users
  min      = 100000
  max      = 999999
}

locals {
  passwords = {
    for user in local.word_users :
    user => format("%s-%d", random_shuffle.word[user].result[0], random_integer.num[user].result)
  }
}


# --------------------------------------------------------------------------------
# USER: John Smith (jsmith)
# --------------------------------------------------------------------------------

# Create Secrets Manager container for user credentials.
resource "aws_secretsmanager_secret" "jsmith_secret" {
  name        = "jsmith_ad_credentials_vscode"
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
    password = local.passwords["jsmith"]
  })
}


# --------------------------------------------------------------------------------
# USER: Emily Davis (edavis)
# --------------------------------------------------------------------------------

# Create Secrets Manager container for user credentials.
resource "aws_secretsmanager_secret" "edavis_secret" {
  name        = "edavis_ad_credentials_vscode"
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
    password = local.passwords["edavis"]
  })
}


# --------------------------------------------------------------------------------
# USER: Raj Patel (rpatel)
# --------------------------------------------------------------------------------

# Create Secrets Manager container for user credentials.
resource "aws_secretsmanager_secret" "rpatel_secret" {
  name        = "rpatel_ad_credentials_vscode"
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
    password = local.passwords["rpatel"]
  })
}


# --------------------------------------------------------------------------------
# USER: Amit Kumar (akumar)
# --------------------------------------------------------------------------------

# Create Secrets Manager container for user credentials.
resource "aws_secretsmanager_secret" "akumar_secret" {
  name        = "akumar_ad_credentials_vscode"
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
    password = local.passwords["akumar"]
  })
}
