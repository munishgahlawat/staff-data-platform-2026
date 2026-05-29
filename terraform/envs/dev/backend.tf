terraform {
  backend "gcs" {
    bucket = "data-platform-eng-tfstate"
    prefix = "staffde/dev"
  }
}
