variable "account_id" {
  description = "Cloudflare account ID (dashboard → any zone → right sidebar)."
  type        = string
}

variable "forward_to" {
  description = "Inbox that hello@ and security@superkeypass.com forward to."
  type        = string
}
