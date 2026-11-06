output "bucket" {
  description = "S3 bucket holding the built site"
  value       = module.static_site.bucket_name
}

output "cloudfront_id" {
  description = "CloudFront distribution id (for cache invalidation)"
  value       = module.static_site.distribution_id
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain"
  value       = module.static_site.distribution_domain
}

output "url" {
  description = "Public site URL"
  value       = "https://${var.domain_name}"
}

output "name_servers" {
  description = "Route53 nameservers delegated at the registrar"
  value       = module.route53_zone.name_servers
}
