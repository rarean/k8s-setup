#!/bin/bash

# This should be run as root or with sudo rights.
# device /dev/xvdf should be second disk or one that is not mounted as primary
# Script based on Docker-CE instructions >= v17.03.x
# https://docs.docker.com/storage/storagedriver/device-mapper-driver/#configure-direct-lvm-mode-for-production

if [ -z "$1" ]; then
  echo "please enter device name to setup (e.g. xvdf from /dev/xvdf )"
  exit 0
fi

# ensure docker is stopped first
systemctl stop docker >> /dev/null

echo "setup lvm for $1"
pvcreate /dev/$1

vgcreate docker /dev/$1

lvcreate --wipesignatures y -n thinpool docker -l 95%VG

lvcreate --wipesignatures y -n thinpoolmeta docker -l 1%VG

lvconvert -y --zero n -c 512K --thinpool docker/thinpool --poolmetadata docker/thinpoolmeta

echo " "
echo "create docker-thinpool.profile and monitor it"
cat > /etc/lvm/profile/docker-thinpool.profile <<'EOF'
activation {
  thin_pool_autoextend_threshold=80
  thin_pool_autoextend_percent=20
}
EOF

lvchange --metadataprofile docker-thinpool docker/thinpool

lvs -o+seg_monitor

echo " "
echo "backup /var/lib/docker"
mkdir /var/lib/docker.bk
mv /var/lib/docker/* /var/lib/docker.bk

echo " "
echo "create daemon.json with new settings"
cat > /etc/docker/daemon.json <<'EOF'
{
    "storage-driver": "devicemapper",
    "storage-opts": [
    "dm.thinpooldev=/dev/mapper/docker-thinpool",
    "dm.use_deferred_removal=true",
    "dm.use_deferred_deletion=true"
    ]
}
EOF

echo " "
echo "To finish: Restart docker and verify new settings with docker info"
echo "If Docker is configured correctly, the Data file and Metadata file values are blank, and the pool name is docker-thinpool"

