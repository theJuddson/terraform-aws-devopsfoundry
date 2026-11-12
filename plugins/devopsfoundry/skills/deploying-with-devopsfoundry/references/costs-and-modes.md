# Costs and modes

Rough monthly costs in us-east-1 before any traffic. Say which mode you're proposing, and give the person the
figure before they approve `bin/new-app`. These are DevOpsFoundry's own estimates from its README; for a precise
figure use AWS's pricing data, not mental arithmetic.

| Mode | Fixed cost | Notes |
| --- | --- | --- |
| Dedicated stack | about $50/month (NAT gateway ~$33, load balancer ~$16), plus tasks | Own network, load balancer and cluster |
| Dedicated, no NAT (`enable_nat_gateway = false` and `tasks_in_public_subnets = true`) | about $16/month, plus tasks | Tasks get public IPs for outbound only; inbound stays load-balancer-only. Set both together. Not safe if a third party allowlists the app's outbound address |
| Shared platform (`--shared-platform <slug>`) | the guest's own tasks and database only | Borrows another DevOpsFoundry app's network, NAT, load balancer and cluster. Typical app falls from ~$85 to ~$25/month. Shares that host's failure domain; never destroy a host with guests |

Add-ons: Postgres (`--enable-db`), Redis (`--enable-cache`) and WAF (`create_waf`, about $5/month plus rules and
requests) each cost extra. Graviton (`cpu_architecture = "ARM64"` in `app.tfvars`) is about 20% cheaper per vCPU-hour
when the image's dependencies support arm64.
