FROM ubuntu:22.04

ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd systemd-sysv cron curl iproute2 iputils-ping \
        bash tar gzip ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && (cd /lib/systemd/system/sysinit.target.wants/; \
        for i in *; do [ "$i" = systemd-tmpfiles-setup.service ] || rm -f "$i"; done) \
    && rm -f /lib/systemd/system/multi-user.target.wants/* \
             /etc/systemd/system/*.wants/* \
             /lib/systemd/system/local-fs.target.wants/* \
             /lib/systemd/system/sockets.target.wants/*udev* \
             /lib/systemd/system/sockets.target.wants/*initctl* \
             /lib/systemd/system/basic.target.wants/* \
             /lib/systemd/system/anaconda.target.wants/* \
             /lib/systemd/system/plymouth* \
             /lib/systemd/system/systemd-update-utmp*

RUN mkdir -p /data/mydir \
    && echo "hello from lab1" > /data/mydir/hello.txt \
    && date > /data/mydir/created-at.txt

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

COPY docker/client/backup.service /etc/systemd/system/backup.service
COPY docker/client/backup.timer /etc/systemd/system/backup.timer
COPY docker/client/backup.env.example /etc/backup.env

RUN systemctl enable cron.service backup.timer

VOLUME [ "/sys/fs/cgroup" ]
CMD ["/lib/systemd/systemd"]
