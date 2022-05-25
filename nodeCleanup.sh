#!/usr/bin/env bash
function silence {
    local args="$@"
    ${args} &>/dev/null
} # Silences commands.
function checkPriv { if [[ "$EUID" != 0 ]]; then
    echo "Please run me as root."
    exit 1
fi; }
function red_printf { printf "\033[31m$@\033[0m"; }     # Debugging output.
function green_printf { printf "\033[32m$@\033[0m"; }   # Debugging output.
function yellow_printf { printf "\033[33m$@\033[0m"; }  # Debugging output.
function white_printf { printf "\033[1;37m$@\033[0m"; } # Debugging output.
function white_brackets {
    local args="$@"
    white_printf "["
    printf "${args}"
    white_printf "]"
} # Debugging output.
function echoInfo {
    local args="$@"
    white_brackets $(green_printf "INFO") && echo " ${args}"
} # Debugging output.
function addDockerList {
    DOCKERLIST=/etc/apt/sources.list.d/docker.list
    if [ ! -f "$DOCKERLIST" ]; then
        echoInfo "Adding Docker list to Apt"
        echo "deb http://dkalin-ubr.corp.lego.com/ubuntu/docker/ bionic stable" > $DOCKERLIST
        wget -qO - http://dkalin-ubr.corp.lego.com/ubuntu/docker/gpg | apt-key add -
    fi
}
function docker_restart {
    docker_stop
    echoInfo "Sleeping 5 seconds to start docker again."
    sleep 5
    docker_start
}
function docker_start {
    systemctl reset-failed docker.service
    daemon_reload
    systemctl is-active docker.service >/dev/null 2>&1 && echoInfo "Docker already started." || systemctl start docker.service
}
function docker_stop {
    systemctl stop docker.socket
    sleep 5
    systemctl is-active docker.service >/dev/null 2>&1 && systemctl stop docker.service || echoInfo "Docker.service already stopped."
}
function daemon_reload { systemctl daemon-reload; }
function containerd_restart { systemctl restart containerd; }
function rmMetaDB { silence "rm -f /var/lib/containerd/io.containerd.metadata.v1.bolt/meta.db"; }
function docker_purge {
    ## Purges Docker installation and /data/lib/docker in addition to default directories
    if [ -x "$(command -v docker)" ]; then
        echoInfo "Docker is present - purging... It takes a while,please wait ..."
        silence "apt-get purge -y docker-engine docker docker.io docker-ce"
        silence "apt-get autoremove -y --purge docker-engine docker docker.io docker-ce"
        echoInfo "Docker is successfully purged"
    else
        echoInfo "Docker is not present - nothing to purge"
    fi
    echoInfo "Leftover docker directories to be cleaned"
    rm -rf /var/lib/docker /etc/docker
    rm /etc/apparmor.d/docker
    rm -rf /var/run/docker.sock
    rm -rf /data/lib/docker
    rm -rf /etc/docker/daemon.json
    echoInfo "Leftover Docker directories are cleaned"
}
function docker_install {
    echoInfo "Docker is installing! Please wait..."
    silence "apt update -y"
    silence "apt install docker-ce -y"
    echoInfo "Docker is successfully installed"
}
function docker_root {
    ## Changing the docker's default /var/lib/docker to /data/lib/docker
    echoInfo "Changing Docker's work directory to /data/lib/docker.Please wait..."
    mkdir -p /data/lib/docker
    sed -i -e 's@ExecStart=/usr/bin/dockerd -H fd://@ExecStart=/usr/bin/dockerd -g /data/lib/docker -H fd://@g' /lib/systemd/system/docker.service
    docker_stop
    #wait for stopped docker daemon
        echoInfo "Waiting for Docker daemon to stop"
    while [[ $(ps aux | grep -i docker | grep -v grep) ]]; do
        echo -n "."
    done
    daemon_reload
    rsync -aqxP /var/lib/docker/ /data/lib/docker
    # docker_start
    # echoInfo "New working dir for Docker! Check below:"
    # ps aux | grep -i docker | grep -v grep
}
function log_rotation {
    ## Enabling Docker's log rotation
    echoInfo "Enabling Docker's log rotation"
    echo '{
          "log-driver": "json-file",
          "log-opts": {
              "max-size": "10m",
              "max-file": "3"
          },
          "data-root": "/data/lib/docker"
  }' >>/etc/docker/daemon.json
    # docker_restart
    echoInfo "Docker's log rotation is enabled"
}
function rmContainers {
    ## Removes ALL containers.
    echoInfo "docker rm -f $(docker ps -aq)" &&
        echoInfo "Successfully removed all Docker containers." ||
        echoInfo "No Docker containers exist! Skipping."
}
function rmVolumes {
    ## Removes ALL volumes.
    echoInfo "docker volume rm $(docker volume ls -q)" &&
        echoInfo "Successfully removed all Docker volumes." ||
        echoInfo "No Docker volumes exist! Skipping."
}
function rmLocs {
    ## Removes all Rancher and Kubernetes related folders.
    declare -a FOLDERS
    FOLDERS=("/etc/ceph"
        "/etc/cni"
        "/etc/kubernetes"
        "/opt/cni"
        "/opt/rke"
        "/run/secrets/kubernetes.io"
        "/run/calico"
        "/run/flannel"
        "/var/lib/calico"
        "/var/lib/etcd"
        "/var/lib/cni"
        "/var/lib/kubelet"
        "/var/lib/rancher/rke/log"
        "/var/log/containers"
        "/var/log/pods"
        "/var/run/calico"
    )
    for loc in "${FOLDERS[@]}"; do
        if [ -d ${loc} ]; then
            silence "rm -fr ${loc}" &&
                echoInfo "${loc} successfully deleted."
        else
            echoInfo "${loc} not found! Skipping."
        fi
    done
    ## Removes Rancher installation from default installation directory.
    local rancher_loc="/opt/rancher"
    if [ -d ${rancher_loc} ]; then
        silence "rm -fr /opt/rancher" &&
            echoInfo "Rancher successfully removed from ${rancher_loc}."
    else
        echoInfo "Rancher not found in ${rancher_loc}! Skipping."
    fi
}
function cleanFirewall {
    ## Removes Firewall entries related to Rancher or Kubernetes.
    IPTABLES="/sbin/iptables"
    cat /proc/net/ip_tables_names | while read table; do
        silence "$IPTABLES -t $table -L -n" | while read c chain rest; do
            if test "X$c" = "XChain"; then
                silence "$IPTABLES -t $table -F $chain"
            fi
        done
        silence "$IPTABLES -t $table -X"
    done
}
function rmDevs {
    ## Unmounts all Rancher and Kubernetes related virtual devices and volumes.
    for mount in \
        $(mount | grep tmpfs | grep '/var/lib/kubelet' | awk '{ print $3 }') \
        /var/lib/kubelet /var/lib/rancher; do silence "umount ${mount}"; done
}
############################################
############################################
# Checks if user running the script is root.
checkPriv
# Ensures Docker is actually running.
docker_start
# Removes ALL containers.
rmContainers
# Removes ALL volumes.
rmVolumes
# Adds Docker list to Apt
addDockerList
# Purges Docker installation
docker_purge
# Installs Docker
docker_install
# Changes Docker's default from /var/lib/docker to /data/lib/docker
docker_root
# Enables log rotation for Docker
log_rotation
# Removes all Rancher and Kubernetes related folders.
# Removes Rancher installation from default installation directory.
rmLocs
# Unmounts all Rancher and Kubernetes related virtual devices and volumes.
rmDevs
# Removes metadata database.
rmMetaDB
# Removes Firewall entries related to Rancher or Kubernetes.
cleanFirewall
# Restarts services, to apply previous removals.
containerd_restart
# Slowed down Docker restart. Needs a pause, because else it complains about "too quick" restarts.
docker_restart
echoInfo "Cleanup completed."
