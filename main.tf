#Bucket to Store Website

resource "google_storage_bucket" "website_bucket" {
  name     = "this-is-a-test-bucket-by-lambert-terraform"
  location = "US"
}

#Make new object public
resource "google_storage_object_access_control" "public_rule" {
  object = google_storage_bucket_object.static_site_src.name
  bucket = google_storage_bucket.website_bucket.name
  role   = "READER"
  entity = "allUsers"
}

#Upload index.html to bucket
resource "google_storage_bucket_object" "static_site_src" {
  name         = "index.html"
  source       = "../website/index.html"
  bucket       = google_storage_bucket.website_bucket.name
  content_type = "text/html"
}

#Reserve a Static IP Address
resource "google_compute_global_address" "website_ip" {
  name = "website-lb-ip"
}

#Get the managed DNS zone
data "google_dns_managed_zone" "dns_zone" {
  name = "terraform-demo"
}

#Add the Ip to the DNS
resource "google_dns_record_set" "website" {
  name         = "website.${data.google_dns_managed_zone.dns_zone.dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  rrdatas      = [google_compute_global_address.website_ip.address]
}

#Add the bucket as a CDN backend
resource "google_compute_backend_bucket" "website-backend" {
  name        = "website-bucket"
  bucket_name = google_storage_bucket.website_bucket.name
  description = "containes files needed for the website"
  enable_cdn  = true
}

#Create HTTPS certificate
resource "google_compute_managed_ssl_certificate" "website" {
    provider = google-beta
    name = "website-cert"
    managed {
        domains = [google_dns_record_set.website.name]
    }
  
}

#GCP URL MAP
resource "google_compute_url_map" "website" {
  name            = "website-url-map"
  default_service = google_compute_backend_bucket.website-backend.self_link
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.website-backend.self_link
  }
}

# GCP HTTP Proxy LB
resource "google_compute_target_http_proxy" "website" {
  name    = "website-target-proxy"
  url_map = google_compute_url_map.website.self_link
}

#GCP Global Forwarding Rule
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "website-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.website_ip.address
  ip_protocol           = "TCP"
  port_range            = "80" #Best practice is to use 443 for HTTPS. 80 is for HTTPS
  target                = google_compute_target_http_proxy.website.self_link

}