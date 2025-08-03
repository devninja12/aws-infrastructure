provider "aws" {
  region = "us-east-2"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
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
    description = "Tomcat Web UI"
    from_port   = 8080
    to_port     = 8080
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------- Maven --------------------
resource "aws_instance" "Maven" {
  ami                    = "ami-068d5d5ed1eeea07c"
  instance_type          = "t3.small"
  key_name               = "cloudspin"
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y maven
              echo "<html><body><h1>Maven Installed</h1></body></html>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "maven-server"
  }
}

# ---------------- Tomcat --------------------
resource "aws_instance" "Tomcat" {
  ami                    = "ami-068d5d5ed1eeea07c"
  instance_type          = "t3.small"
  key_name               = "cloudspin"
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
    wget https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.107/bin/apache-tomcat-9.0.107.zip
    unzip apache-tomcat-9.0.107.zip
    mv apache-tomcat-9.0.107 tomcat9
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

# ---------------- SonarQube --------------------
resource "aws_instance" "Sonarqube" {
  ami                    = "ami-068d5d5ed1eeea07c"
  instance_type          = "c7i-flex.large"
  key_name               = "cloudspin"
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  user_data = <<-EOF
              #!/bin/bash
              set -e
              dnf install -y unzip curl
              rpm --import https://yum.corretto.aws/corretto.key || true
              curl -Lo /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
              dnf install -y java-17-amazon-corretto-devel --nogpgcheck

              useradd --system --no-create-home --shell /bin/bash sonar
              curl -Lo /tmp/sonarqube.zip https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-10.5.1.90531.zip
              unzip /tmp/sonarqube.zip -d /opt
              mv /opt/sonarqube-10.5.1.90531 /opt/sonarqube
              chown -R sonar:sonar /opt/sonarqube

              cat <<EOT > /etc/systemd/system/sonarqube.service
              [Unit]
              Description=SonarQube service
              After=network.target

              [Service]
              Type=forking
              ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
              ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
              User=sonar
              Group=sonar
              Restart=always
              LimitNOFILE=65536
              LimitNPROC=4096
              TimeoutStartSec=60

              [Install]
              WantedBy=multi-user.target
              EOT

              systemctl daemon-reexec
              systemctl daemon-reload
              systemctl enable sonarqube
              systemctl start sonarqube
              EOF

  tags = {
    Name = "sonarqube-server"
  }
}

output "Maven_public_ip" {
  value = aws_instance.Maven.public_ip
}

output "Tomcat_public_ip" {
  value = aws_instance.Tomcat.public_ip
}

output "Sonarqube_public_ip" {
  value = aws_instance.Sonarqube.public_ip
}
