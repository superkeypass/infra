terraform {
  required_version = ">= 1.6"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
  }
  # State is local for now (handoff decision). Never commit it — see .gitignore.
}

# Reads CLOUDFLARE_API_TOKEN from the environment.
provider "cloudflare" {}

data "cloudflare_zone" "com" {
  name = "superkeypass.com"
}

data "cloudflare_zone" "org" {
  name = "superkeypass.org"
}

locals {
  zones = {
    com = data.cloudflare_zone.com.id
    org = data.cloudflare_zone.org.id
  }
}

# ── Zone settings: SSL Full (strict), Always HTTPS, HSTS, TLS ≥ 1.2 ──────────
resource "cloudflare_zone_settings_override" "this" {
  for_each = local.zones
  zone_id  = each.value

  settings {
    ssl                      = "strict"
    always_use_https         = "on"
    min_tls_version          = "1.2"
    automatic_https_rewrites = "on"

    security_header {
      enabled            = true
      max_age            = 31536000
      include_subdomains = true
      preload            = false # flip to true only once every subdomain is HTTPS-forever
      nosniff            = true
    }
  }
}

# ── Landing page: Cloudflare Pages from superkeypass/website ─────────────────
resource "cloudflare_pages_project" "website" {
  account_id        = var.account_id
  name              = "superkeypass-website"
  production_branch = "main"

  source {
    type = "github"
    config {
      owner                         = "superkeypass"
      repo_name                     = "website"
      production_branch             = "main"
      deployments_enabled           = true
      production_deployment_enabled = true
    }
  }

  build_config {
    build_command   = ""
    destination_dir = ""
  }
}

resource "cloudflare_pages_domain" "apex" {
  account_id   = var.account_id
  project_name = cloudflare_pages_project.website.name
  domain       = "superkeypass.com"
}

resource "cloudflare_record" "apex" {
  zone_id = local.zones.com
  name    = "@"
  type    = "CNAME" # flattened at the apex by Cloudflare
  content = cloudflare_pages_project.website.subdomain
  proxied = true
}

# www and the whole .org zone only need to exist and be proxied so the
# redirect rules below can catch the request. 192.0.2.1 is TEST-NET-1 (never routed).
resource "cloudflare_record" "www" {
  zone_id = local.zones.com
  name    = "www"
  type    = "A"
  content = "192.0.2.1"
  proxied = true
}

resource "cloudflare_record" "org_apex" {
  zone_id = local.zones.org
  name    = "@"
  type    = "A"
  content = "192.0.2.1"
  proxied = true
}

resource "cloudflare_record" "org_www" {
  zone_id = local.zones.org
  name    = "www"
  type    = "A"
  content = "192.0.2.1"
  proxied = true
}

# ── Redirects ────────────────────────────────────────────────────────────────
resource "cloudflare_ruleset" "com_redirects" {
  zone_id = local.zones.com
  name    = "redirects"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules {
    description = "www -> apex"
    expression  = "(http.host eq \"www.superkeypass.com\")"
    action      = "redirect"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = true
        target_url {
          expression = "concat(\"https://superkeypass.com\", http.request.uri.path)"
        }
      }
    }
  }
}

resource "cloudflare_ruleset" "org_redirects" {
  zone_id = local.zones.org
  name    = "redirects"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules {
    description = ".org -> .com"
    expression  = "true"
    action      = "redirect"
    action_parameters {
      from_value {
        status_code           = 301
        preserve_query_string = true
        target_url {
          expression = "concat(\"https://superkeypass.com\", http.request.uri.path)"
        }
      }
    }
  }
}

# ── Email: routing for hello@ and security@, SPF, DMARC ──────────────────────
resource "cloudflare_email_routing_settings" "com" {
  zone_id = local.zones.com
  enabled = true # also creates Cloudflare's MX + SPF include records
}

resource "cloudflare_email_routing_address" "dest" {
  account_id = var.account_id
  email      = var.forward_to # Cloudflare mails a verification link to this address
}

resource "cloudflare_email_routing_rule" "forward" {
  for_each = toset(["hello", "security"])
  zone_id  = local.zones.com
  name     = "${each.key}@ -> inbox"
  enabled  = true

  matcher {
    type  = "literal"
    field = "to"
    value = "${each.key}@superkeypass.com"
  }

  action {
    type  = "forward"
    value = [cloudflare_email_routing_address.dest.email]
  }
}

resource "cloudflare_record" "dmarc" {
  zone_id = local.zones.com
  name    = "_dmarc"
  type    = "TXT"
  content = "v=DMARC1; p=none; rua=mailto:hello@superkeypass.com"
}

# .org sends no mail: lock it down so nobody can spoof it.
resource "cloudflare_record" "org_spf" {
  zone_id = local.zones.org
  name    = "@"
  type    = "TXT"
  content = "v=spf1 -all"
}

resource "cloudflare_record" "org_dmarc" {
  zone_id = local.zones.org
  name    = "_dmarc"
  type    = "TXT"
  content = "v=DMARC1; p=reject;"
}
