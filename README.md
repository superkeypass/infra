# superkeypass/infra

Cloudflare DNS, zone settings, redirects, Pages, and Email Routing for
superkeypass.com / superkeypass.org, as Terraform. State is local for now.

```bash
export CLOUDFLARE_API_TOKEN=…   # Zone:DNS:Edit, Zone:Zone Settings:Edit,
                                # Zone:Dynamic Redirect:Edit, Zone:Email Routing Rules:Edit,
                                # Account:Cloudflare Pages:Edit, Account:Email Routing Addresses:Edit
cp terraform.tfvars.example terraform.tfvars   # fill in account_id + forward_to
terraform init && terraform plan && terraform apply
```

Notes
- The handoff's token scopes (DNS:Edit + Zone Settings:Edit) are **not
  enough** for redirects, Pages, or Email Routing — add the extra scopes above.
- SPF for .com is created by Cloudflare when Email Routing is enabled; DMARC
  starts at `p=none`. `.org` sends no mail, so it gets `-all` / `p=reject`.
- The Pages project needs the Cloudflare GitHub app installed on the
  `superkeypass` org before `apply` can link `superkeypass/website`.
- `forward_to` receives a verification email; forwarding stays inactive until
  that link is clicked.
