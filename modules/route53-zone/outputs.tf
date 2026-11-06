output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "Route53 nameservers — set these as the domain's custom NS at the registrar"
  value       = aws_route53_zone.main.name_servers
}

output "validation_record_fqdns" {
  description = "FQDNs of the ACM validation records, for aws_acm_certificate_validation"
  value       = [for r in aws_route53_record.acm_validation : r.fqdn]
}
