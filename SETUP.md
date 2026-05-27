# Staff Data Engineer - Local Setup Guide
Tested on: macOS, darwin_amd64  
Date: 2026-05-27

## 1. Install gcloud CLI
```bash
brew install --cask google-cloud-sdk
gcloud --version

## 2. Install Terraform via HashiCorp Tap
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform --version

## 3. Download: https://www.docker.com/products/docker-desktop/ Verify:
docker --version

## 4. GCP Authentication
gcloud auth login
gcloud auth application-default login
gcloud config set project data-platform-eng

## 5. Verify BigQuery Access
bq query --use_legacy_sql=false 'SELECT 1 as test'

## 6. Clone Project Repo
git clone https://github.com/munishgahlawat/staff-data-platform-2026
cd staff-data-platform-2026

## 7. Verify Git Setup
git status
git remote -v
git branch

## Final Versions
## gcloud: 569.0.0Terraform: 1.15.4Docker: 29.5.2Quota Project: data-platform-eng

