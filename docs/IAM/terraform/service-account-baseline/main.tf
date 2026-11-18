terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

variable "workload_name" {
  description = "Unique identifier for the microservice or workload (e.g., billing-api)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

# ------------------------------------------------------------------------------
# 1. Google Cloud Service Account (No static keys generated)
# ------------------------------------------------------------------------------
resource "google_service_account" "workload" {
  account_id   = "${var.workload_name}-${var.environment}-sa"
  display_name = "Service Account for ${var.workload_name} (${var.environment})"
  description  = "Managed by Terraform. Do not create static JSON keys."
}

# ------------------------------------------------------------------------------
# 2. AWS IAM Role (EC2/ECS/Lambda Service Trust)
# ------------------------------------------------------------------------------
resource "aws_iam_role" "workload" {
  name = "${var.workload_name}-${var.environment}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "://amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Workload    = var.workload_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# 3. Azure User-Assigned Managed Identity
# ------------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "workload" {
  name                = "${var.workload_name}-${var.environment}-id"
  resource_group_name = "rg-${var.environment}-core"
  location            = "eastus"

  tags = {
    Workload    = var.workload_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

output "gcp_service_account_email" {
  value = google_service_account.workload.email
}

output "aws_iam_role_arn" {
  value = aws_iam_role.workload.arn
}

output "azure_identity_principal_id" {
  value = azurerm_user_assigned_identity.workload.principal_id
}
