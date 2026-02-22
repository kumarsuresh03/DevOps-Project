provider "google" {
  project = "dev-stage-project"
  region  = "asia-south1"
}

# --------------------------------------------------
# Enable Required APIs
# --------------------------------------------------

resource "google_project_service" "compute" {
  project = "dev-stage-project"
  service = "compute.googleapis.com"
}

# --------------------------------------------------
# DEV Storage Bucket
# --------------------------------------------------

resource "google_storage_bucket" "frontend" {
  name     = "dev-stage-frontend-bucket"
  location = "ASIA-SOUTH1"

  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  depends_on = [google_project_service.compute]
}

resource "google_storage_bucket_iam_binding" "public_read" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.objectViewer"
  members = ["allUsers"]
}

# --------------------------------------------------
# DEV Backend Bucket
# --------------------------------------------------

resource "google_compute_backend_bucket" "backend" {
  name        = "frontend-backend"
  bucket_name = google_storage_bucket.frontend.name
  enable_cdn  = true

  depends_on = [google_project_service.compute]
}

# --------------------------------------------------
# STAGE Backend Bucket (NEW)
# --------------------------------------------------

resource "google_compute_backend_bucket" "backend_stage" {
  name        = "stage-backend"
  bucket_name = "stage-frontend-bucket"   # Created from Stage folder
  enable_cdn  = true

  depends_on = [google_project_service.compute]
}

resource "google_compute_backend_bucket" "backend_prod" {
  name        = "prod-backend"
  bucket_name = "prod-frontend-bucket"   # Created from prod folder
  enable_cdn  = true

  depends_on = [google_project_service.compute]
}

# --------------------------------------------------
# Global IP
# --------------------------------------------------

resource "google_compute_global_address" "ip" {
  name = "frontend-ip"

  depends_on = [google_project_service.compute]
}

# --------------------------------------------------
# URL Map (UPDATED FOR STAGE ROUTING)
# --------------------------------------------------

resource "google_compute_url_map" "url_map" {
  name = "frontend-url-map"

  default_service = google_compute_backend_bucket.backend.self_link

  host_rule {
    hosts        = ["*"]
    path_matcher = "env-matcher"
  }

  path_matcher {
    name            = "env-matcher"
    default_service = google_compute_backend_bucket.backend.self_link

    path_rule {
      paths   = ["/stage/*"]
      service = google_compute_backend_bucket.backend_stage.self_link
    }
    path_rule {
      paths   = ["/prod/*"]
      service = google_compute_backend_bucket.backend_prod.self_link
    }
  }

  depends_on = [google_project_service.compute]
}

# --------------------------------------------------
# HTTP Proxy
# --------------------------------------------------

resource "google_compute_target_http_proxy" "proxy" {
  name    = "frontend-http-proxy"
  url_map = google_compute_url_map.url_map.self_link

  depends_on = [google_project_service.compute]
}

# --------------------------------------------------
# Forwarding Rule
# --------------------------------------------------

resource "google_compute_global_forwarding_rule" "rule" {
  name                  = "frontend-rule"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.proxy.self_link
  ip_address            = google_compute_global_address.ip.address

  depends_on = [google_project_service.compute]
}

# --------------------------------------------------
# Output
# --------------------------------------------------

output "cdn_ip" {
  value = google_compute_global_address.ip.address
}