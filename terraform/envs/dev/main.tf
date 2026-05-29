terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  common_labels = {
    owner   = "munish"
    project = "staffde"
    env     = "dev"
    managed = "terraform"
  }
}
# Enable required GCP APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "dataflow.googleapis.com",
    "storage.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
  ])
  project = var.project_id
  service = each.key
  
  disable_on_destroy = false  # Don't turn off APIs when you destroy infra
}

# $50 budget alert
resource "google_billing_budget" "budget" {
  billing_account = var.billing_account_id
  display_name    = "staffde-dev-budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "50"
    }
  }

  threshold_rules {
    threshold_percent = 0.5   # Alert at $25
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 0.9   # Alert at $45
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 1.0   # Alert at $50
    spend_basis       = "CURRENT_SPEND"
  }

  depends_on = [google_project_service.apis]
}
