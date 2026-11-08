# Network layout and toggles: subnet CIDRs per AZ, the optional NAT gateway,
# and the database/cache security groups. Plans only, against a mocked AWS
# provider: no account is touched.

mock_provider "aws" {
  # The module slices this list by az_count and names subnets after it.
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
}

variables {
  name = "demo"
}

run "defaults_two_azs_with_nat_and_no_data_tier" {
  command = plan

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16" && aws_vpc.main.tags.Name == "demo-vpc"
    error_message = "The VPC must use the default CIDR and the <name>-vpc tag shared-platform looks it up by."
  }
  assert {
    condition     = aws_vpc.main.enable_dns_support && aws_vpc.main.enable_dns_hostnames
    error_message = "The VPC must resolve DNS names (needed for RDS/ElastiCache endpoints and VPC endpoints)."
  }
  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "By default the network spans two AZs, one public and one private subnet each."
  }
  assert {
    condition     = aws_subnet.public[*].cidr_block == ["10.0.0.0/24", "10.0.1.0/24"]
    error_message = "Public subnets must take the first /24s of the VPC."
  }
  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.0.10.0/24", "10.0.11.0/24"]
    error_message = "Private subnets must start at the 11th /24, clear of the public range."
  }
  assert {
    condition     = aws_subnet.public[*].availability_zone == ["us-east-1a", "us-east-1b"] && aws_subnet.private[*].availability_zone == ["us-east-1a", "us-east-1b"]
    error_message = "Each AZ must get one public and one private subnet."
  }
  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch]) && !anytrue([for s in aws_subnet.private : s.map_public_ip_on_launch])
    error_message = "Only public subnets may hand out public IPs."
  }
  assert {
    condition     = aws_subnet.public[0].tags.Name == "demo-public-us-east-1a" && aws_subnet.private[1].tags.Name == "demo-private-us-east-1b"
    error_message = "Subnet Name tags must follow <name>-<tier>-<az>, which shared-platform matches on."
  }
  assert {
    condition     = length(aws_eip.nat) == 1 && length(aws_nat_gateway.main) == 1
    error_message = "The NAT gateway is on by default so private tasks can reach ECR and CloudWatch."
  }
  assert {
    condition     = length(aws_route_table.private.route) == 1
    error_message = "With the NAT on, the private route table must carry a default route."
  }
  assert {
    condition     = length(aws_route_table_association.public) == 2 && length(aws_route_table_association.private) == 2
    error_message = "Every subnet must be associated with its tier's route table."
  }
  assert {
    condition     = aws_security_group.alb.name == "demo-alb-sg" && aws_security_group.alb.tags.Name == "demo-alb-sg"
    error_message = "The ALB security group must be named and tagged <name>-alb-sg, which shared-platform looks up."
  }
  assert {
    condition     = toset([for r in aws_security_group.alb.ingress : r.from_port]) == toset([80, 443])
    error_message = "The ALB must admit HTTP and HTTPS from the internet."
  }
  assert {
    condition     = aws_security_group_rule.api_ingress_from_alb.from_port == 8080 && aws_security_group_rule.api_ingress_from_alb.to_port == 8080
    error_message = "Tasks must admit the default container port from the ALB."
  }
  assert {
    condition     = length(aws_security_group.rds) == 0 && length(aws_security_group_rule.rds_ingress_from_api) == 0
    error_message = "No database security group unless the database is enabled."
  }
  assert {
    condition     = length(aws_security_group.redis) == 0 && length(aws_security_group_rule.redis_ingress_from_api) == 0
    error_message = "No cache security group unless the cache is enabled."
  }
  assert {
    condition     = output.rds_security_group_id == null && output.redis_security_group_id == null
    error_message = "Disabled data-tier security group outputs must be null."
  }
}

run "nat_disabled_drops_nat_but_keeps_private_routing" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = length(aws_eip.nat) == 0 && length(aws_nat_gateway.main) == 0
    error_message = "enable_nat_gateway = false must not create the ~$33/month NAT or its EIP."
  }
  # With no route blocks the provider leaves `route` computed, so its length is
  # unknown at plan; a route to the missing NAT would fail on aws_nat_gateway.main[0].
  assert {
    condition     = length(aws_route_table_association.private) == 2
    error_message = "Private subnets must keep their route table association without the NAT."
  }
}

run "az_count_and_cidr_shape_subnets" {
  command = plan

  variables {
    az_count = 3
    vpc_cidr = "10.20.0.0/16"
  }

  assert {
    condition     = aws_subnet.public[*].cidr_block == ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
    error_message = "Public subnets must be carved from vpc_cidr, one per AZ."
  }
  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
    error_message = "Private subnets must be carved from vpc_cidr, one per AZ."
  }
  assert {
    condition     = aws_subnet.private[2].availability_zone == "us-east-1c"
    error_message = "A third AZ must be used when az_count = 3."
  }
  assert {
    condition     = length(aws_route_table_association.public) == 3 && length(aws_route_table_association.private) == 3
    error_message = "Every subnet must be associated with its tier's route table."
  }
}

run "database_and_cache_get_dedicated_security_groups" {
  command = plan

  variables {
    enable_database = true
    enable_cache    = true
    db_port         = 5433
    cache_port      = 6380
    container_port  = 3000
  }

  assert {
    condition     = length(aws_security_group.rds) == 1 && aws_security_group.rds[0].name == "demo-rds-sg"
    error_message = "enable_database must create the <name>-rds-sg group."
  }
  assert {
    condition     = length(aws_security_group_rule.rds_ingress_from_api) == 1 && aws_security_group_rule.rds_ingress_from_api[0].from_port == 5433 && aws_security_group_rule.rds_ingress_from_api[0].to_port == 5433
    error_message = "The database must admit db_port from the tasks."
  }
  assert {
    condition     = length(aws_security_group.redis) == 1 && aws_security_group.redis[0].name == "demo-redis-sg"
    error_message = "enable_cache must create the <name>-redis-sg group."
  }
  assert {
    condition     = length(aws_security_group_rule.redis_ingress_from_api) == 1 && aws_security_group_rule.redis_ingress_from_api[0].from_port == 6380 && aws_security_group_rule.redis_ingress_from_api[0].to_port == 6380
    error_message = "The cache must admit cache_port from the tasks."
  }
  assert {
    condition     = aws_security_group_rule.api_ingress_from_alb.from_port == 3000 && aws_security_group_rule.api_ingress_from_alb.to_port == 3000
    error_message = "Tasks must admit container_port from the ALB."
  }
}
