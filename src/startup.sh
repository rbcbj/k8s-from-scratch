#!/usr/bin/env bash

# https://wiki.debian.org/Teams/pkg-systemd/Packaging
# https://www.debian.org/doc/manuals/maint-guide/
# https://www.debian.org/doc/manuals/maint-guide/dother.en.html#maintscripts

alias k="kubectl --kubeconfig /etc/kubernetes/pki/kube-admin.kubeconfig"

kubectl --kubeconfig /etc/kubernetes/pki/kube-admin.kubeconfig \
  apply \
  -f /etc/kubernetes/config/kube-apiserver-to-kubelet.yaml