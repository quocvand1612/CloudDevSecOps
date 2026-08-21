output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_compute_subnet_ids" {
  description = "List of IDs of private compute subnets"
  value       = aws_subnet.private_compute[*].id
}

output "isolated_data_subnet_ids" {
  description = "List of IDs of isolated data subnets"
  value       = aws_subnet.isolated_data[*].id
}

output "private_compute_route_table_id" {
  description = "ID of the private compute route table"
  value       = aws_route_table.private_compute.id
}
