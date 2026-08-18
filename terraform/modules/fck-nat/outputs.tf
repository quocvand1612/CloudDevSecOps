output "instance_id" {
  description = "ID of the fck-nat EC2 instance"
  value       = aws_instance.fck_nat.id
}

output "public_ip" {
  description = "Public Elastic IP assigned to fck-nat"
  value       = aws_eip.fck_nat.public_ip
}

output "network_interface_id" {
  description = "Primary network interface ID used as NAT target in route table"
  value       = aws_instance.fck_nat.primary_network_interface_id
}
