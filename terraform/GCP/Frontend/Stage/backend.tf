terraform {
  backend "gcs" {
    bucket  = "remot-terraform-state"
    prefix  = "frontend-cdn/stage/stage"
  }
}