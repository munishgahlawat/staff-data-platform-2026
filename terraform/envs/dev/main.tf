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

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_prefix" {
  description = "Prefix for all resource names" 
  type        = string
  default     = "staffde"
}

locals {
  name_prefix = "${var.project_prefix}-${var.environment}"
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
# --- Service Account for Dataflow ---
resource "google_service_account" "dataflow_sa" {
  account_id   = "${local.name_prefix}-dataflow-sa"
  display_name = "Dataflow Service Account for ${var.environment}"
  description  = "Runs Dataflow jobs and accesses GCS/BQ"
}

# --- IAM: Let the SA do its job ---
resource "google_project_iam_member" "dataflow_worker" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "bq_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "bq_dataeditor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "gcs_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}
# --- GCS Buckets ---
resource "google_storage_bucket" "raw" {
  name                        = "${local.name_prefix}-raw-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true # allows terraform destroy even if not empty. DEV ONLY.

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "staging" {
  name                        = "${local.name_prefix}-staging-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true # DEV ONLY

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
}

# --- BigQuery Datasets ---
resource "google_bigquery_dataset" "raw" {
  dataset_id                 = "${var.project_prefix}_raw_${var.environment}"
  location                   = var.region
  delete_contents_on_destroy = true # DEV ONLY
  description                = "Raw landing zone for ${var.environment}"
}

resource "google_bigquery_dataset" "analytics" {
  dataset_id                 = "${var.project_prefix}_analytics_${var.environment}"
  location                   = var.region
  delete_contents_on_destroy = true # DEV ONLY
  description                = "Clean analytics tables for ${var.environment}"
}

# --- Grant SA access to buckets ---
resource "google_storage_bucket_iam_member" "dataflow_raw_admin" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_storage_bucket_iam_member" "dataflow_staging_admin" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataflow_sa.email}"
}
