provider "google" {
  project = "dev-stage-project"
  region  = "asia-south1"
}

# -----------------------------
# PROD STORAGE BUCKET
# -----------------------------
resource "google_storage_bucket" "frontend_prod" {
  name     = "prod-frontend-bucket"
  location = "ASIA-SOUTH1"

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true

  versioning {
    enabled = true
  }

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }
}

resource "google_storage_bucket_iam_binding" "prod_public" {
  bucket  = google_storage_bucket.frontend_prod.name
  role    = "roles/storage.objectViewer"
  members = ["allUsers"]
}

output "prod_bucket_name" {
  value = google_storage_bucket.frontend_prod.name
}