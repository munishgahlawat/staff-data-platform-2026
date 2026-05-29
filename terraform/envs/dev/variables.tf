variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "Default region"
  type        = string
  default     = "us-central1"
}

variable "billing_account_id" {
  description = "Billing account ID: gcloud beta billing accounts list"
  type        = string
}
