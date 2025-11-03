resource "aws_eip" "nat" {
  tags = {
    Name = "${local.prefix}-nat"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_zone1.id
  tags = {
    Name = "${local.prefix}-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}
