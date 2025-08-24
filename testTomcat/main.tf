provider "aws" {
  region = "us-east-2"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "test_ssh" {
  name        = "test_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SonarQube Web UI"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Tomcat Web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------- Tomcat --------------------
resource "aws_instance" "Tomcat" {
  ami                    = "ami-068d5d5ed1eeea07c"
  instance_type          = "t3.small"
  key_name               = "testinfra.pem"
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

    user_data = <<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/user-data.log 2>&1

    echo "Setting timezone and hostname"
    timedatectl set-timezone America/Toronto
    hostnamectl set-hostname tomcat

    echo "Installing packages"
    yum install -y wget git unzip java-21-openjdk-devel

    echo "Installing Tomcat"
    cd /opt
    wget https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.107/bin/apache-tomcat-9.0.108.zip
    unzip apache-tomcat-9.0.108.zip
    mv apache-tomcat-9.0.108 tomcat9
    chmod -R 777 /opt/tomcat9
    chown -R ec2-user /opt/tomcat9

    echo "Configuring Tomcat user"
    sed -i '/<\/tomcat-users>/i\  <user username="kubeadmin" password="admin123" roles="manager-gui,admin-gui,manager-script"/>' /opt/tomcat9/conf/tomcat-users.xml
    
    sed -i '/<Valve className="org.apache.catalina.valves.RemoteAddrValve"/{N;s|.*\n.*|<!--\n&\n-->|}' /opt/tomcat9/webapps/host-manager/META-INF/context.xml
    
    sed -i '/<Valve className="org.apache.catalina.valves.RemoteAddrValve"/{N;s|.*\n.*|<!--\n&\n-->|}' /opt/tomcat9/webapps/manager/META-INF/context.xml    

    ln -s /opt/tomcat9/bin/startup.sh /usr/bin/starttomcat
    ln -s /opt/tomcat9/bin/shutdown.sh /usr/bin/stoptomcat
    /opt/tomcat9/bin/startup.sh

    echo "Tomcat installation completed"
  EOF


  tags = {
    Name = "tomcat-server"
  }
}


output "Tomcat_public_ip" {
  value = aws_instance.Tomcat.public_ip
}
