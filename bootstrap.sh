#!/usr/bin/env bash

set -ex

ROOT_DIR=$(realpath .)
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
SRC_DIR="${ROOT_DIR}/src"

if [[ -n "${BUILD_DEB}" ]]; then
  rm -rf "./dist"
  rm -rf "./build"
fi

# ======================================================================================================================
# Download binaries
# ======================================================================================================================

#sed -i '' -e 's/arm/amd/g' $SRC_DIR/downloads.txt

if [[ ! -d "${BUILD_DIR}/downloads" ]]; then
  mkdir -p "${BUILD_DIR}/downloads"

  wget -q --show-progress \
    --https-only \
    --timestamping \
    -P "build/downloads" \
    -i "${SRC_DIR}/downloads.txt" || true
fi

# ======================================================================================================================
# Setup environment variables
# ======================================================================================================================

source "${SRC_DIR}/certs/common.env"

# ======================================================================================================================
# Bootstrap deb package
# ======================================================================================================================
mkdir -p "${DIST_DIR}"
rm -rf "${DIST_DIR}/DEBIAN"
cp -r "${SRC_DIR}/DEBIAN" "${DIST_DIR}/DEBIAN"

mkdir -p "${DIST_DIR}/usr/local/bin/"
cp "${BUILD_DIR}/downloads/kubectl" "${DIST_DIR}/usr/local/bin/"
chmod +x "${DIST_DIR}/usr/local/bin/kubectl"

# ======================================================================================================================
# Bootstrap yaml setup
# ======================================================================================================================
rm    -rf "${DIST_DIR}/etc/kubernetes/k8s"
mkdir -p  "${DIST_DIR}/etc/kubernetes/"
cp    -r  "${SRC_DIR}/k8s" "${DIST_DIR}/etc/kubernetes"

# ======================================================================================================================
# Generating certs
# ======================================================================================================================

pki_ca() {
  local ca_name=${1:-ca}

  mkdir -p "${BUILD_DIR}/certs/"

  openssl genrsa -out "${BUILD_DIR}/certs/${ca_name}.key" 4096

  openssl req -x509 -new -sha512 -nodes \
    -key "${BUILD_DIR}/certs/${ca_name}.key" -days 3653 \
    -config "${SRC_DIR}/certs/${ca_name}.cnf" \
    -out "${BUILD_DIR}/certs/${ca_name}.crt"
}

pki_cert() {
  local ca_name=${1:-ca}
  local cert_name=${2}

  mkdir -p "${BUILD_DIR}/certs/"

  envsubst < "${SRC_DIR}/certs/${cert_name}.cnf" > "${BUILD_DIR}/certs/${cert_name}-generated.cnf"

  openssl genrsa -out "${BUILD_DIR}/certs/${cert_name}.key" 4096

  openssl req -new -key "${BUILD_DIR}/certs/${cert_name}.key" \
    -out "${BUILD_DIR}/certs/${cert_name}.csr" \
    -config "${BUILD_DIR}/certs/${cert_name}-generated.cnf"

  # openssl req  -noout -text -in "${i}.csr" | less

  openssl x509 -req -days 3653 \
    -in "${BUILD_DIR}/certs/${cert_name}.csr" \
    -extfile "${BUILD_DIR}/certs/${cert_name}-generated.cnf"\
    -extensions v3_ext \
    -sha256 \
    -CA "${BUILD_DIR}/certs/${ca_name}.crt" \
    -CAkey "${BUILD_DIR}/certs/${ca_name}.key" \
    -CAcreateserial \
    -out "${BUILD_DIR}/certs/${cert_name}.crt"

    # openssl x509  -noout -text -in "${i}.crt" | less
}

pki_ca "ca"

# https://kubernetes.io/docs/concepts/overview/components/
certs=( \
  "kube-admin" \
  "service-accounts" \
  # node
  "kube-proxy" "kubelet" \
  "kube-router" \
  # control plane
  "kube-apiserver" "kube-scheduler" "kube-controller-manager" \
)

# https://kubernetes.io/docs/tasks/administer-cluster/certificates/#openssl
# https://kubernetes.io/docs/setup/best-practices/certificates/
for i in ${certs[*]}; do
  pki_cert "ca" "$i"
done

# ======================================================================================================================
# Generating kubeconfig
# ======================================================================================================================

# node kubeconfig

# https://kubernetes.io/docs/reference/access-authn-authz/node/#overview
mkdir -p "${DIST_DIR}/etc/kubernetes/pki/"
cp "${BUILD_DIR}/certs/ca.crt" \
  "${BUILD_DIR}/certs/kubelet.crt" \
  "${BUILD_DIR}/certs/kubelet.key" \
  "${DIST_DIR}/etc/kubernetes/pki/"

export K8S_NODE_ID="kubelet"

cat <<CMD | docker run --rm -i \
           -v `pwd`:/k8s \
           --workdir "/k8s/dist/etc/kubernetes/pki/" \
           ubuntu:20.04 \
           bash
export PATH="\$PATH:/k8s/dist/usr/local/bin"

kubectl config set-cluster ${K8S_CLUSTER} \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://${K8S_CLUSTER_DOMAIN}:6443 \
  --kubeconfig=${K8S_NODE_ID}.kubeconfig

kubectl config set-credentials system:node:${K8S_NODE} \
  --client-certificate=${K8S_NODE_ID}.crt \
  --client-key=${K8S_NODE_ID}.key \
  --embed-certs=true \
  --kubeconfig=${K8S_NODE_ID}.kubeconfig

kubectl config set-context default \
  --cluster=${K8S_CLUSTER} \
  --user=system:node:${K8S_NODE} \
  --kubeconfig=${K8S_NODE_ID}.kubeconfig

kubectl config use-context default \
  --kubeconfig=${K8S_NODE_ID}.kubeconfig
CMD

# kube-proxy kubeconfig

mkdir -p "${DIST_DIR}/etc/kubernetes/pki/"
cp "${BUILD_DIR}/certs/ca.crt" \
  "${BUILD_DIR}/certs/kube-proxy.crt" \
  "${BUILD_DIR}/certs/kube-proxy.key" \
  "${DIST_DIR}/etc/kubernetes/pki/"

cat <<CMD | docker run --rm -i \
           -v `pwd`:/k8s \
           --workdir "/k8s/dist/etc/kubernetes/pki/" \
           ubuntu:20.04 \
           bash
export PATH="\$PATH:/k8s/dist/usr/local/bin"

kubectl config set-cluster ${K8S_CLUSTER} \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://${K8S_CLUSTER_DOMAIN}:6443 \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate=kube-proxy.crt \
  --client-key=kube-proxy.key \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=${K8S_CLUSTER} \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default \
  --kubeconfig=kube-proxy.kubeconfig
CMD

# kube-controller-manager kubeconfig

mkdir -p "${DIST_DIR}/etc/kubernetes/pki/"
cp "${BUILD_DIR}/certs/ca.crt" \
  "${BUILD_DIR}/certs/kube-controller-manager.crt" \
  "${BUILD_DIR}/certs/kube-controller-manager.key" \
  "${DIST_DIR}/etc/kubernetes/pki/"

cat <<CMD | docker run --rm -i \
           -v `pwd`:/k8s \
           --workdir "/k8s/dist/etc/kubernetes/pki/" \
           ubuntu:20.04 \
           bash
export PATH="\$PATH:/k8s/dist/usr/local/bin"

kubectl config set-cluster ${K8S_CLUSTER} \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://${K8S_CLUSTER_DOMAIN}:6443 \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=kube-controller-manager.crt \
  --client-key=kube-controller-manager.key \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=${K8S_CLUSTER} \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context default \
  --kubeconfig=kube-controller-manager.kubeconfig
CMD

# kube-scheduler kubeconfig

mkdir -p "${DIST_DIR}/etc/kubernetes/pki/"
cp "${BUILD_DIR}/certs/ca.crt" \
  "${BUILD_DIR}/certs/kube-scheduler.crt" \
  "${BUILD_DIR}/certs/kube-scheduler.key" \
  "${DIST_DIR}/etc/kubernetes/pki/"

cat <<CMD | docker run --rm -i \
           -v `pwd`:/k8s \
           --workdir "/k8s/dist/etc/kubernetes/pki/" \
           ubuntu:20.04 \
           bash
export PATH="\$PATH:/k8s/dist/usr/local/bin"

kubectl config set-cluster ${K8S_CLUSTER} \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://${K8S_CLUSTER_DOMAIN}:6443 \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.crt \
  --client-key=kube-scheduler.key \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster=${K8S_CLUSTER} \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context default \
  --kubeconfig=kube-scheduler.kubeconfig
CMD

# kube-admin kubeconfig

mkdir -p "${DIST_DIR}/etc/kubernetes/pki/"
cp "${BUILD_DIR}/certs/ca.crt" \
  "${BUILD_DIR}/certs/kube-admin.crt" \
  "${BUILD_DIR}/certs/kube-admin.key" \
  "${DIST_DIR}/etc/kubernetes/pki/"

cat <<CMD | docker run --rm -i \
           -v `pwd`:/k8s \
           --workdir "/k8s/dist/etc/kubernetes/pki/" \
           ubuntu:20.04 \
           bash
export PATH="\$PATH:/k8s/dist/usr/local/bin"

kubectl config set-cluster ${K8S_CLUSTER} \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-admin.kubeconfig

kubectl config set-credentials kube-admin \
  --client-certificate=kube-admin.crt \
  --client-key=kube-admin.key \
  --embed-certs=true \
  --kubeconfig=kube-admin.kubeconfig

kubectl config set-context default \
  --cluster=${K8S_CLUSTER} \
  --user=kube-admin \
  --kubeconfig=kube-admin.kubeconfig

kubectl config use-context default \
  --kubeconfig=kube-admin.kubeconfig
CMD

# kube-router kubeconfig

mkdir -p "${DIST_DIR}/etc/kubernetes/pki/"
cp "${BUILD_DIR}/certs/ca.crt" \
  "${BUILD_DIR}/certs/kube-router.crt" \
  "${BUILD_DIR}/certs/kube-router.key" \
  "${DIST_DIR}/etc/kubernetes/pki/"

cat <<CMD | docker run --rm -i \
           -v `pwd`:/k8s \
           --workdir "/k8s/dist/etc/kubernetes/pki/" \
           ubuntu:20.04 \
           bash
export PATH="\$PATH:/k8s/dist/usr/local/bin"

kubectl config set-cluster ${K8S_CLUSTER} \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-router.kubeconfig

kubectl config set-credentials kube-router \
  --client-certificate=kube-router.crt \
  --client-key=kube-router.key \
  --embed-certs=true \
  --kubeconfig=kube-router.kubeconfig

kubectl config set-context default \
  --cluster=${K8S_CLUSTER} \
  --user=kube-router \
  --kubeconfig=kube-router.kubeconfig

kubectl config use-context default \
  --kubeconfig=kube-router.kubeconfig
CMD

# ======================================================================================================================
# Setup Data Encryption config
# ======================================================================================================================

# Generating the Data Encryption Config and Key
# https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data
# https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#understanding-the-encryption-at-rest-configuration]
mkdir -p "${BUILD_DIR}/configs/"
envsubst < "${SRC_DIR}/configs/encryption-config.yaml" > "${BUILD_DIR}/configs/encryption-config.yaml"

# Copy the encryption-config.yaml encryption config file to each controller instance

# ======================================================================================================================
# Bootstrap ETCD
# ======================================================================================================================
pushd "${BUILD_DIR}/downloads"

export ETCD_VERSION="etcd-v3.4.27-linux-amd64"

mkdir -p "${DIST_DIR}/usr/local/bin"
tar zxvf "${ETCD_VERSION}.tar.gz"
mv "${ETCD_VERSION}/etcd"* "${DIST_DIR}/usr/local/bin"
rm -rf "${ETCD_VERSION}"

mkdir -p "${DIST_DIR}/etc/etcd" \
         "${DIST_DIR}/var/lib/etcd"
chmod 700 "${DIST_DIR}/var/lib/etcd"

cp "${BUILD_DIR}/certs/ca.crt" \
 "${BUILD_DIR}/certs/kube-apiserver.key" \
 "${BUILD_DIR}/certs/kube-apiserver.crt" \
 "${DIST_DIR}/etc/etcd/"

mkdir -p "${DIST_DIR}/etc/systemd/system/"
cp "${SRC_DIR}/services/etcd.service" "${DIST_DIR}/etc/systemd/system/"

popd

# ======================================================================================================================
# Bootstrap Control Plane
# ======================================================================================================================

cp "${BUILD_DIR}/downloads/kube-apiserver" \
  "${BUILD_DIR}/downloads/kube-controller-manager" \
  "${BUILD_DIR}/downloads/kube-scheduler" \
  "${DIST_DIR}/usr/local/bin"
chmod +x "${DIST_DIR}/usr/local/bin/kube"*

mkdir -p "${DIST_DIR}/etc/systemd/system/"
envsubst < "${SRC_DIR}/services/kube-apiserver.service"          > "${DIST_DIR}/etc/systemd/system/kube-apiserver.service"
envsubst < "${SRC_DIR}/services/kube-controller-manager.service" > "${DIST_DIR}/etc/systemd/system/kube-controller-manager.service"
envsubst < "${SRC_DIR}/services/kube-scheduler.service"          > "${DIST_DIR}/etc/systemd/system/kube-scheduler.service"

mkdir -p "${DIST_DIR}/etc/kubernetes/config"
envsubst < "${SRC_DIR}/configs/kube-scheduler.yaml"            > "${DIST_DIR}/etc/kubernetes/config/kube-scheduler.yaml"

# Configure Api Server
mkdir -p "${DIST_DIR}/var/lib/kubernetes/"

cp "${BUILD_DIR}/certs/ca.crt" "${BUILD_DIR}/certs/ca.key" \
  "${BUILD_DIR}/certs/kube-apiserver.key" "${BUILD_DIR}/certs/kube-apiserver.crt" \
  "${BUILD_DIR}/certs/service-accounts.key" "${BUILD_DIR}/certs/service-accounts.crt" \
  "${DIST_DIR}/etc/kubernetes/pki/"

cp "${BUILD_DIR}/configs/encryption-config.yaml" \
  "${DIST_DIR}/etc/kubernetes/config/"

# ======================================================================================================================
# Bootstrap worker node
# ======================================================================================================================

mkdir -p \
  "${DIST_DIR}/etc/containerd/" \
  "${DIST_DIR}/etc/kubernetes/config" \
  "${DIST_DIR}/etc/kubernetes/manifests" \
  "${DIST_DIR}/etc/systemd/system/" \
  "${DIST_DIR}/opt/cni/bin" \
  "${DIST_DIR}/etc/cni/net.d" \
  "${DIST_DIR}/var/lib/kubelet" \
  "${DIST_DIR}/var/lib/kubernetes" \
  "${DIST_DIR}/var/run/kubernetes" \
  "${DIST_DIR}/bin/" \
  "${DIST_DIR}/usr/local/bin/"

# Binaries
mkdir -p "${BUILD_DIR}/containerd"
tar -xvf "${BUILD_DIR}/downloads/containerd-1.7.8-linux-amd64.tar.gz" -C "${BUILD_DIR}/containerd"
mv "${BUILD_DIR}/containerd/bin/"* "${DIST_DIR}/bin/"
rm -rf "${BUILD_DIR}/containerd"

tar -xvf "${BUILD_DIR}/downloads/cni-plugins-linux-amd64-v1.3.0.tgz" -C "${DIST_DIR}/opt/cni/bin/"

tar -xvf "${BUILD_DIR}/downloads/crictl-v1.28.0-linux-amd64.tar.gz" -C "${DIST_DIR}/usr/local/bin/"

cat <<CRICTL | tee "${DIST_DIR}/etc/crictl.yaml"
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
CRICTL

cp "${BUILD_DIR}/downloads/runc.amd64" "${DIST_DIR}/usr/local/bin/runc"
cp "${BUILD_DIR}/downloads/kubelet"    "${DIST_DIR}/usr/local/bin/"
cp "${BUILD_DIR}/downloads/kube-proxy" "${DIST_DIR}/usr/local/bin/"

chmod +x "${DIST_DIR}/usr/local/bin/"*

# Network
# https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/#installation

envsubst < "${SRC_DIR}/configs/10-bridge.conf" > "${DIST_DIR}/etc/cni/net.d/10-bridge.conf"
mv "${DIST_DIR}/etc/cni/net.d/10-bridge.conf" "${DIST_DIR}/etc/cni/net.d/10-bridge.conf-disabled"
cp "${SRC_DIR}/configs/99-loopback.conf" "${DIST_DIR}/etc/cni/net.d/"

# kube-router
tar zxvf "${BUILD_DIR}/downloads/kube-router_2.0.1_linux_amd64.tar.gz" -C "${DIST_DIR}/usr/local/bin" kube-router

envsubst < "${SRC_DIR}/configs/10-kuberouter.conf" > "${DIST_DIR}/etc/cni/net.d/10-kuberouter.conf"
envsubst < "${SRC_DIR}/services/kube-router.service" > "${DIST_DIR}/etc/systemd/system/kube-router.service"

# Containerd
cp "${SRC_DIR}/configs/containerd-config.toml" "${DIST_DIR}/etc/containerd/config.toml"
cp "${SRC_DIR}/services/containerd.service"    "${DIST_DIR}/etc/systemd/system/"

# Kubelet
envsubst < "${SRC_DIR}/services/kubelet.service"    > "${DIST_DIR}/etc/systemd/system/kubelet.service"
envsubst < "${SRC_DIR}/configs/kubelet-config.yaml" > "${DIST_DIR}/etc/kubernetes/config/kubelet-config.yaml"

# Kube Proxy
envsubst < "${SRC_DIR}/services/kube-proxy.service"    > "${DIST_DIR}/etc/systemd/system/kube-proxy.service"
envsubst < "${SRC_DIR}/configs/kube-proxy-config.yaml" > "${DIST_DIR}/etc/kubernetes/config/kube-proxy-config.yaml"

# ======================================================================================================================
# Building deb package
# ======================================================================================================================

if [[ -n "${BUILD_DEB}" ]]; then
  docker run --rm \
    -v `pwd`:/k8s \
    --workdir "/k8s" \
    ubuntu:20.04 \
    dpkg-deb --root-owner-group --build dist
fi