# Create a VPC
resource "aws_vpc" "wdgtl-vpc" {
  cidr_block           = "20.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "VPC-20.0.0.0"
  }
}

resource "aws_subnet" "wdgtl-public-subnet" {
  vpc_id                  = aws_vpc.wdgtl-vpc.id
  cidr_block              = "20.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "public-subnet-us-east-1a-20.0.1.0"
  }
}

resource "aws_subnet" "wdgtl-private-subnet" {
  vpc_id                  = aws_vpc.wdgtl-vpc.id
  cidr_block              = "20.0.2.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "us-east-1a"

  tags = {
    Name = "private-subnet-us-east-1a-20.0.2.0"
  }
}

resource "aws_internet_gateway" "wdgtl-igw" {
  vpc_id = aws_vpc.wdgtl-vpc.id

  tags = {
    Name = "wdgtl-igw"
  }
}

resource "aws_route_table" "wdgtl-rt" {
  vpc_id = aws_vpc.wdgtl-vpc.id

  tags = {
    Name = "wdgtl-rt"
  }
}

resource "aws_route" "wdgtl-route" {
  route_table_id         = aws_route_table.wdgtl-rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wdgtl-igw.id
}

resource "aws_route_table_association" "wdgtl-public-assoc" {
  subnet_id      = aws_subnet.wdgtl-public-subnet.id
  route_table_id = aws_route_table.wdgtl-rt.id
}

# Launch master node
resource "aws_instance" "k8s_master" {
  ami           = var.ami["master"]
  instance_type = var.instance_type["master"]
  tags = {
    Name = "k8s-master"
  }
  key_name        = aws_key_pair.k8s.key_name
  security_groups = [aws_security_group.k8s_master.id]
  subnet_id       = aws_subnet.wdgtl-public-subnet.id

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("k8s")
    host        = self.public_ip
  }
  provisioner "file" {
    source      = "./master.sh"
    destination = "/home/ubuntu/master.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/master.sh",
      "sudo sh /home/ubuntu/master.sh k8s-master"
    ]
  }
  provisioner "local-exec" {
    command = "ansible-playbook -i '${self.public_ip},' playbook.yml"
  }
}

# Launch worker nodes
resource "aws_instance" "k8s_worker" {
  count         = var.worker_instance_count
  ami           = var.ami["worker"]
  instance_type = var.instance_type["worker"]
  tags = {
    Name = "k8s-worker-${count.index}"
  }
  key_name        = aws_key_pair.k8s.key_name

  security_groups = [aws_security_group.k8s_worker.id]
  subnet_id       = aws_subnet.wdgtl-public-subnet.id


  depends_on      = [aws_instance.k8s_master]
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("k8s")
    host        = self.public_ip
  }
  provisioner "file" {
    source      = "./worker.sh"
    destination = "/home/ubuntu/worker.sh"
  }
  provisioner "file" {
    source      = "./join-command.sh"
    destination = "/home/ubuntu/join-command.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/worker.sh",
      "sudo sh /home/ubuntu/worker.sh k8s-worker-${count.index}",
      "sudo sh /home/ubuntu/join-command.sh"
    ]
  }
}