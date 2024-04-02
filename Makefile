.PHONY: common
common:
	touch src/etc/crictl.yaml

	docker run \
		--rm \
		-it \
		-e PATH="/usr/local/scripts:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
		-v $(shell pwd)/src/etc/kubernetes:/etc/kubernetes \
		-v $(shell pwd)/src/usr/src/kubernetes:/usr/src/kubernetes \
		-v $(shell pwd)/src/var/lib/kubernetes/:/var/lib/kubernetes/ \
		\
		-v $(shell pwd)/src/etc/containerd:/etc/containerd \
		-v $(shell pwd)/src/etc/crictl.yaml:/etc/crictl.yaml \
		-v $(shell pwd)/src/etc/cni/:/etc/cni/ \
		-v $(shell pwd)/src/opt/cni:/opt/cni \
		\
		-v $(shell pwd)/src/etc/systemd/system/:/etc/systemd/system/ \
		\
		-v $(shell pwd)/src/etc/etcd:/etc/etcd \
		-v $(shell pwd)/src/var/lib/etcd:/var/lib/etcd \
		\
		-v $(shell pwd)/src/usr/local/sbin:/usr/local/sbin \
		-v $(shell pwd)/src/usr/local/scripts:/usr/local/scripts \
		ubuntu:20.04 \
		$(CMD)

.PHONY: dev
dev:
	make common CMD=bash

.PHONY: clean
clean:
	git clean -df .
	rm -rfv dist

.PHONY: build
build: clean
	make common CMD=bootstrap_singlenode

.PHONY: bundle
bundle: build
	rm -rfv dist || true

	docker run --rm \
		-v `pwd`/dist:/k8s-build \
		-v `pwd`/src:/k8s \
		--workdir "/k8s" \
		ubuntu:20.04 \
		dpkg-deb --root-owner-group --build /k8s /k8s-build/k8s-single-node.deb