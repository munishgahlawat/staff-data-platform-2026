Here you go. Copy everything below into terraform/README.mdmarkdown# Staff Data Platform: Day 1 Setup Runbook v1.0

**Scope:** GCP + Terraform foundation for data engineering  
**SLA:** 60 min fresh, 30 min repeat  
**Outputs:** Remote state, $50 budget, Service Account, GCS buckets, BQ datasets  
**Project:** `data-platform-eng` | **Region:** `us-central1` | **Prefix:** `staffde`

## Step 0: One-Time Prerequisites - 5 min
Run once per laptop. Skip if already done.

```bash
# 1. Install CLI tools
brew install google-cloud-sdk terraform

# 2. Authenticate - run BOTH commands
gcloud auth login
gcloud auth application-default login

# 3. Set defaults
gcloud config set project data-platform-eng
gcloud config set compute/region us-central1

# 4. CRITICAL: Set quota project for ADC to fix billing API 403s
gcloud auth application-default set-quota-project data-platform-eng
export GOOGLE_CLOUD_QUOTA_PROJECT=data-platform-eng
echo 'export GOOGLE_CLOUD_QUOTA_PROJECT=data-platform-eng' >> ~/.zshrc

# 5. Get billing account ID and save it
gcloud billing accounts list
# Example: <replace_with_real_billing_acount - "gcloud billing accounts list"> | REPLACE in code belowStep 1: Repo + Remote State Bucket - 5 minbashmkdir staff-data-platform-2026 && cd staff-data-platform-2026
git init
mkdir -p terraform/envs/dev

# Create GCS bucket for terraform state - global name, create once
gsutil mb -p data-platform-eng -l us-central1 gs://data-platform-eng-tfstate
gsutil versioning set on gs://data-platform-eng-tfstate

# Basic gitignore
cat > .gitignore << 'EOF'
terraform/.terraform/
terraform/*.tfstate
terraform/*.tfstate.*
terraform/.terraform.lock.hcl
EOF

git add . && git commit -m "init: repo + state bucket + gitignore"Step 2: Terraform Base Config - 5 minFile: terraform/envs/dev/main.tfhclterraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "data-platform-eng-tfstate"
    prefix = "staffde/dev"
  }
}

provider "google" {
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "data-platform-eng"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
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
}Initialize:bashcd terraform/envs/dev
terraform init
cd ../../..
git add terraform/ && git commit -m "feat: terraform init with remote state"Step 3: Enable APIs + Create Budget - 10 minAppend to terraform/envs/dev/main.tf:hcl# --- Enable Required APIs ---
locals {
  apis = [
    "bigquery.googleapis.com",
    "dataflow.googleapis.com", 
    "storage.googleapis.com",
    "cloudbilling.googleapis.com",
    "billingbudgets.googleapis.com"
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# --- $50 Hard Budget ---
resource "google_billing_budget" "budget" {
  billing_account = "<replace_with_real_billing_acount - "gcloud billing accounts list">" # REPLACE with your billing ID from Step 0
  display_name    = "${local.name_prefix}-budget"
  amount {
    specified_amount {
      currency_code = "USD"
      units         = "50"
    }
  }
  budget_filter {
    projects = ["projects/${var.project_id}"]
  }
  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 0.9 }
  threshold_rules { threshold_percent = 1.0 }
}Apply:bashcd terraform/envs/dev
terraform plan
terraform apply # type: yes
cd ../../..
git add terraform/ && git commit -m "feat: enable APIs + $50 budget"Step 4: Service Account + IAM - 5 minAppend to terraform/envs/dev/main.tf:hcl# --- Dataflow Service Account ---
resource "google_service_account" "dataflow_sa" {
  account_id   = "${local.name_prefix}-dataflow-sa"
  display_name = "Dataflow Service Account for ${var.environment}"
  description  = "Runs Dataflow jobs and accesses GCS/BQ"
}

# --- Least-Privilege IAM ---
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
}Apply:bashcd terraform/envs/dev
terraform apply # type: yes
cd ../../..
git add terraform/ && git commit -m "feat: add dataflow SA + IAM roles"Step 5: GCS + BigQuery Resources - 10 minAppend to terraform/envs/dev/main.tf:hcl# --- GCS Buckets ---
resource "google_storage_bucket" "raw" {
  name                        = "${local.name_prefix}-raw-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true # DEV ONLY - remove in prod
  versioning { enabled = true }
  lifecycle_rule {
    condition { age = 30 }
    action { type = "Delete" }
  }
}

resource "google_storage_bucket" "staging" {
  name                        = "${local.name_prefix}-staging-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true # DEV ONLY
  lifecycle_rule {
    condition { age = 7 }
    action { type = "Delete" }
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

# --- Grant SA Bucket Access ---
resource "google_storage_bucket_iam_member" "dataflow_raw_admin" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_storage_bucket_iam_member" "dataflow_staging_admin" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataflow_sa.email}"
}Apply:bashcd terraform/envs/dev
terraform apply # type: yes
cd ../../..
git add terraform/ && git commit -m "feat: add GCS buckets + BQ datasets" && git pushStep 6: Verification Checklist - 2 minbash# 1. Budget exists
gcloud billing budgets list --billing-account=<replace_with_real_billing_acount - "gcloud billing accounts list">

# 2. Service Account exists  
gcloud iam service-accounts list --filter="email:staffde-dev-dataflow-sa"

# 3. Buckets exist
gsutil ls -p data-platform-eng | grep staffde-dev

# 4. Datasets exist
bq ls --project_id=data-platform-eng | grep staffde

# 5. Terraform state clean
cd terraform/envs/dev && terraform plan # Should say "No changes"Troubleshooting: Common ErrorsError MessageRoot CauseFix Command403: Your application has authenticated using end user credentials... requires a quota projectADC missing quota projectexport GOOGLE_CLOUD_QUOTA_PROJECT=data-platform-engSERVICE_DISABLED: billingbudgets.googleapis.comProvider not using billing projectAlready fixed in provider block aboveError: Reference to undeclared local value "name_prefix"Missing locals blockAdd locals + variable blocks from Step 2409: Already Exists on bucketGCS bucket names are globalChange project_prefix variable to something uniquePromoting to Prod - 5 mincp -r terraform/envs/dev terraform/envs/prodIn prod/main.tf change:environment = "prod"prefix = "staffde/prod" in backend blockBudget units = "500"Remove all force_destroy = true and delete_contents_on_destroy = truecd terraform/envs/prod && terraform init && terraform applyFinal Architecturejavascriptdata-platform-eng
├── GCS: staffde-dev-raw-data-platform-eng      # Immutable raw files, 30d TTL
├── GCS: staffde-dev-staging-data-platform-eng  # Dataflow temp, 7d TTL  
├── BQ: staffde_raw_dev                         # Raw tables
├── BQ: staffde_analytics_dev                   # Modeled tables
├── IAM: staffde-dev-dataflow-sa@               # Least-privilege SA
└── Budget: $50 hard limit                      # Alerts at 50/90/100%End state: Run gsutil cp file.csv gs://staffde-dev-raw-data-platform-eng/ and process with Dataflow using the SA.javascript*Paste the whole thing. This is your playbook. Next time: 30 min, zero StackOverflow.*
