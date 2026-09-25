# The rehearsal's two stand-ins (../README.md), one image:
# - the machine that deploys: Kamal (this image's own) and the kit, run as
#   `kit … -d rehearsal` from the checkout;
# - the server Kamal deploys to: sshd and a Docker CLI on this machine's Docker.
FROM ghcr.io/basecamp/kamal:v2.12.0
RUN apk add --no-cache bash curl git jq openssh-server openssh-sftp-server \
 && ssh-keygen -A \
 && mkdir -p /root/.ssh && chmod 700 /root/.ssh
# Kamal's image runs `kamal` by default; here the command is given.
ENTRYPOINT []
CMD ["bash"]
