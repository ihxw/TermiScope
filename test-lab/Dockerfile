FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      systemd systemd-sysv openssh-server sudo curl ca-certificates \
      iproute2 iputils-ping procps vim-tiny nftables \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd \
 && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
 && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && echo 'root:testpass' | chpasswd \
 && useradd -m -s /bin/bash testuser \
 && echo 'testuser:testpass' | chpasswd \
 && echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/testuser

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
