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
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "private-subnet-us-east-1a-20.0.2.0"
  }
}

resource "aws_internet_gateway" "wdgtl-gw" {
  vpc_id = aws_vpc.wdgtl-vpc.id

  tags = {
    Name = "wdgtl-igw"
  }
}

/* 
resource "aws_route_table" "tfrm-public-rt" {
  vpc_id = aws_vpc.tfrm-vpc.id

  tags = {
    Name = "dev-public-rt"
  }
}

resource "aws_route" "default-route" {
  route_table_id         = aws_route_table.tfrm-public-rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.tfrm-gw.id
}

resource "aws_route_table_association" "tfrm-public-assoc" {
  subnet_id      = aws_subnet.tfrm-public-subnet.id
  route_table_id = aws_route_table.tfrm-public-rt.id
}

resource "aws_key_pair" "tfrm-auth" {
  key_name   = "tfrm-key"
  public_key = file("C:\\Users\\malac\\.ssh\\tfrm-key.pub")
}

resource "aws_instance" "dev-node" {
  ami                    = data.aws_ami.server_ami.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.tfrm-auth.id
  vpc_security_group_ids = [aws_security_group.tfrm-sg.id]
  subnet_id              = aws_subnet.tfrm-public-subnet.id
  user_data              = file("userdata.tpl")

  root_block_device {
    volume_size = 10
  }

  tags = {
    Name = "dev-node"
  }
}
*/

# -------------------------------------------------------------------

# Launch master node
resource "aws_instance" "k8s_master" {
  ami                         = var.ami["master"]
  instance_type               = var.instance_type["master"]
  key_name                    = aws_key_pair.k8s.key_name
  vpc_security_group_ids      = [aws_security_group.wdgtl-master-sg.id]
  subnet_id                   = aws_subnet.wdgtl-public-subnet.id
  associate_public_ip_address = true

  tags = {
    Name = "k8s-master"
  }

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
  count                       = var.worker_instance_count
  ami                         = var.ami["worker"]
  instance_type               = var.instance_type["worker"]
  key_name                    = aws_key_pair.k8s.key_name
  vpc_security_group_ids      = [aws_security_group.wdgtl-worker-sg.id]
  subnet_id                   = aws_subnet.wdgtl-public-subnet.id
  depends_on                  = [aws_instance.k8s_master]
  associate_public_ip_address = true

  tags = {
    Name = "k8s-worker-${count.index}"
  }

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