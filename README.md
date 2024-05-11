# Single node k8s from scratch

This setup is heavily inspired in [Kubernetes the hard way](https://github.com/kelseyhightower/kubernetes-the-hard-way).

The main focus for this repo is to enable new users to understand how kubernetes setup works. There is a steep learning curve with this process and I hope this can also help you join the k8s wagon. :D

## Caveats

You can proceed with the build of the `deb` package with: 
```
$ make bundle
```

then, proceed with the install:
```
$ dpkg -i <package>.deb
```
to fix missing packages, proceed with:
```
$ apt-get install -f
```

## Usage

The execution of this repo will create a deb file with a full featured k8s single node install.

- Running k8s 1.28
- Using kube-router which will enable network policies

*YOU SHOULD NOT USE THIS FOR PRODUCTION* 

Please, before using this for anything else, be sure that you are aware of the steps needed to harden your installation.
