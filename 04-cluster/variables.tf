# ================================================================================
# FILE: variables.tf
# ================================================================================
#
# Purpose:
#   Define input variables for Active Directory naming and supporting VPC
#   resource identification.
#
# Naming Model:
#   - dns_zone : Fully Qualified Domain Name for AD DNS namespace.
#   - realm    : Kerberos realm (uppercase dns_zone).
#   - netbios  : Short legacy domain name (<= 15 characters).
#
# Notes:
#   - realm should equal upper(dns_zone) for Kerberos compatibility.
#   - netbios should be uppercase and avoid special characters.
#
# ================================================================================


# ================================================================================
# SECTION: Active Directory DNS Zone (FQDN)
# ================================================================================

variable "dns_zone" {
  description = "Active Directory DNS zone (FQDN)"
  type        = string
  default     = "rstudio.mikecloud.com"
}


# ================================================================================
# SECTION: Kerberos Realm
# ================================================================================

variable "realm" {
  description = "Kerberos realm (uppercase DNS zone)"
  type        = string
  default     = "RSTUDIO.MIKECLOUD.COM"
}


# ================================================================================
# SECTION: NetBIOS Short Domain Name
# ================================================================================

variable "netbios" {
  description = "NetBIOS short domain name"
  type        = string
  default     = "RSTUDIO"
}


# ================================================================================
# SECTION: VPC Naming
# ================================================================================

variable "vpc_name" {
  description = "Name for the VPC resource"
  type        = string
  default     = "rstudio-vpc"
}
