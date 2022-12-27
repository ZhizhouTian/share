---
author: zhizhoutian
title: How to setup a qGPU k8s cluster from scratch
---

## 1. How to install k8s on master node

```bash
#!/bin/bash

dir=$(cd `dirname $0`;pwd)
log_file="${dir}/log/master.log"
[  ! -L ${dir}/log -a ! -d ${dir}/log  ] && mkdir ${dir}/log
exec 1>$log_file
exec 2>&1

function log {
    echo `### date +%F-%T` ">>" $1
}

set -x

# install docker
sudo yum install -y yum-utils
sudo yum-config-manager     --add-repo     https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
sudo docker run hello-world

log "success to install docker"

# install k8s
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=kubernetes
enabled=1
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
       https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

cat <<EOF | sudo tee /root/schedconfig.yaml
apiVersion: kubescheduler.config.k8s.io/v1beta1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: /etc/kubernetes/scheduler.conf
extenders:
- urlPrefix: http://qgpu-scheduler:12345/scheduler
  filterVerb: filter
  prioritizeVerb: priorities
  weight: 10
  bindVerb: bind
  nodeCacheCapable: true
  managedResources:
  - name: tke.cloud.tencent.com/qgpu-core
  - name: tke.cloud.tencent.com/qgpu-memory
EOF

cat <<EOF | sudo tee /root/kubeadm.yaml
apiVersion: kubeadm.k8s.io/v1beta2
# imageRepository: registry.docker.com/zhizhoutian
kind: ClusterConfiguration
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.10.0.0/16
scheduler:
  extraArgs:
    config: /etc/kubernetes/scheduler-config.yaml
  extraVolumes:
    - name: schedulerconfig
      hostPath: /root/schedconfig.yaml
      mountPath: /etc/kubernetes/scheduler-config.yaml
      readOnly: true
      pathType: "File"
EOF

sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

sudo yum install kubeadm-1.20.9-0 kubectl-1.20.9-0 kubelet-1.20.9-0 -y

sudo systemctl start kubelet
sudo systemctl enable --now kubelet

log "success to install k8s"

# enable containerd cri plugins
sed -i 's/^disabled_plugins = \["cri"\]/\# disabled_plugins = \["cri"\]/' /etc/containerd/config.toml

systemctl restart containerd
#kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=${localip}
kubeadm init --config /root/kubeadm.yaml
log "success to init kubeadm"

# correct crictl settings
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: true
pull-image-on-create: false
EOF

# add kubectl env
export KUBECONFIG=/etc/kubernetes/admin.conf
alias k=kubectl
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.bashrc
echo "alias k=kubectl" >> ~/.bashrc

log "success to init kubectl"

# add network cni
# kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/tigera-operator.yaml
kubectl apply -f https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml

log "success to init cni"

log "init cluster finished"
```

### master node install issue one

You may encounter this problem, because we can not access k8s.gcr.io in mainland

```bash
[preflight] You can also perform this action in beforehand using 'kubeadm config images pull'
error execution phase preflight: [preflight] Some fatal errors occurred:
	[ERROR ImagePull]: failed to pull image k8s.gcr.io/kube-apiserver:v1.20.15: output: Error response from daemon: Get "https://k8s.gcr.io/v2/": net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)
, error: exit status 1
```

How to fix:

1. push all related docker images to dockerhub
2. config kubeadm to use this repo

```bash
add this config into kubeadm.yaml
imageRepository: registry.docker.com/zhizhoutian
```

### master node install issue two

You may encounter flannel crash issue.
We can fix this by specifying the master's ip as 10.244.0.0.

## 2. How to initialize worker node

```bash
#!/bin/bash

set -x

dir=$(cd `dirname $0`;pwd)
log_file="${dir}/log/master.log"
[  ! -L ${dir}/log -a ! -d ${dir}/log  ] && mkdir ${dir}/log
exec 1>$log_file
exec 2>&1

function log {
    echo `### date +%F-%T` ">>" $1
}

# install docker
sudo yum install -y yum-utils
sudo yum-config-manager     --add-repo     https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
sudo docker run hello-world

log "success to install docker"

# install k8s
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=kubernetes
enabled=1
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
       https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

sudo yum install kubeadm-1.20.9-0 kubectl-1.20.9-0 kubelet-1.20.9-0 -y

sudo systemctl start kubelet
sudo systemctl enable --now kubelet

# enable containerd cri plugins
sed -i 's/^disabled_plugins = \["cri"\]/\# disabled_plugins = \["cri"\]/' /etc/containerd/config.toml

systemctl restart containerd

log "success to install k8s"

# correct crictl settings
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: true
pull-image-on-create: false
EOF

# add kubectl env
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.bashrc
echo "alias k=kubectl" >> ~/.bashrc

log "success to init kubectl"
```

## 3. Join worker to master node

You can find `kubeadm join xxx` command in master's installation log, like this:

```bash
kubeadm join 10.0.0.49:6443 --token 3j532m.to3vsdb0br70aoxe \
    --discovery-token-ca-cert-hash sha256:9b23cf672c6ea2ea0a229bc03bdca0829c8523d09cdd840228bc99952c3276f5
```

Then login to the worker, and execute the above command.

## 4. Grate worker kubectl execution capbility

config kubectl for remote worker node access

```bash
copy the /etc/kubernetes/admin.conf file on master node to the remote workers node
```

Then you can execute kubectl command from both master and workers

## 5. Set worker role(not necessary)

```bash
kubectl label node vm-0-4-centos node-role.kubernetes.io/worker=worker
kubectl get node
```

## 6. Import qgpu-images images to your own repo

download qgpu-images:

```bash
wget https://qgpu-idc-1259309934.cos.ap-shanghai.myqcloud.com/v1.0.2/qgpu-images.tgz
tar -xvf qgpu-images.tgz
cd /root/qgpu-images/
bash ./import.sh
```

## 7. Install helm utils

```bash
curl -L https://get.helm.sh/helm-v3.8.0-linux-amd64.tar.gz | sudo tar -C /usr/local/bin -xz linux-amd64/helm --strip-components=1
```

## 8. Install GPU driver

```bash
wget "http://mirrors.tencentyun.com/install/GPU/NVIDIA-Linux-x86_64-515.65.01.run"
bash ./NVIDIA-Linux-x86_64-515.65.01.run
```

## 9. Install qGPU k8s plugins with helm

```bash
wget https://qgpu-idc-1259309934.cos.ap-shanghai.myqcloud.com/v1.0.2/qgpu-operator.tgz
```

latest version is 1.0.2

```bash
# do not install gpu driver
# install gpu operator also
helm install --generate-name \
    --set driver.enabled=false \
    --set devicePlugin.enabled=true \
    --set global.repository="zhizhoutian" \
    ./qgpu-operator.tgz
```

## 10. Update kube-scheduler configration

you may encounter this problem when creating qgpu docker

```bash
Error scheduling pod; retrying" err="Post \"http://qgpu-scheduler:12345/scheduler/filter\": dial tcp: lookup qgpu-scheduler on 183.60.82.98:53: no such host" pod="default/cuda-test
```

Solution:

```bash
QGPU_SCHEDULER_SVC_IP=$(kubectl get svc -n kube-system qgpu-scheduler  -o jsonpath="{.spec.clusterIP}")
sed -i "s/qgpu-scheduler/$QGPU_SCHEDULER_SVC_IP/g" /root/schedconfig.yaml

# trigger kube-scheduler restart by modifying the configration file
sudo mv /etc/kubernetes/manifests/kube-scheduler.yaml kube-scheduler.yaml
sudo mv kube-scheduler.yaml /etc/kubernetes/manifests/kube-scheduler.yaml
```

## 11. Try to create a qgpu docker

qgpu docker test yaml:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: qgpu-test
spec:
  containers:
  - name: qgpu-test
    image: zhizhoutian/qgpu
    command: [ "sleep", "12345" ]
    resources:
      limits:
        tke.cloud.tencent.com/qgpu-core: 50
        tke.cloud.tencent.com/qgpu-memory: 5
```

## 12. 如何配置节点的调度策略

kubectl label nodes vm-0-4-centos tke.cloud.tencent.com/qgpu-schedule-policy=fixed-share
kubectl get nodes --show-labels vm-0-4-centos | grep policy

cat /proc/qgpu/0/policy
