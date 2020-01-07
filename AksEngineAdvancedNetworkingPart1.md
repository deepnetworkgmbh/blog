# Understanding Networking Options in Azure AKS-Engine [Part 1]

- [Understanding Networking Options in Azure AKS-Engine [Part 1]](#understanding-networking-options-in-azure-aks-engine-part-1)
- [Introduction](#introduction)
- [Pre-requisites](#pre-requisites)
- [Infrastructure](#infrastructure)
  - [The Virtual Network](#the-virtual-network)
  - [API Model](#api-model)
  - [Build Script](#build-script)
- [Networking Options of AKS-Engine](#networking-options-of-aks-engine)
  - [Azure Container Networking](#azure-container-networking)
  - [Kubenet](#kubenet)
- [References](#references)

# Introduction
AKS Engine provides convenient tooling to quickly bootstrap Kubernetes clusters on Azure. By leveraging ARM (Azure Resource Manager), AKS Engine helps you create, destroy and maintain clusters provisioned with basic IaaS resources in Azure. AKS Engine is also the library used by AKS for performing these operations to provide managed service implementations.

In this document, we are going to use [AKS Engine](https://github.com/Azure/aks-engine) to deploy a brand new cluster with 2 different networking options (kubenet and azure cni) into an existing or pre-created virtual network.

# Pre-requisites
- You need an Azure subscription. If you don't have one, you can [sign up for an account](https://azure.microsoft.com/).
- Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest).
- Install [AKS Engine](https://github.com/Azure/aks-engine/releases) (As of writing, the latest version is v0.43.3)

# Infrastructure

## The Virtual Network

We will deploy a virtual network that contains two subnets:

- 10.10.0.0/24
- 10.20.0.0/24

The first one will be used for the master nodes and the second one for the agent nodes.

The Azure Resource Manager template used to deploy this virtual network is:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {  },
  "variables": {  },
  "resources": [
    {
      "apiVersion": "2017-06-01",
      "location": "[resourceGroup().location]",
      "name": "aks-vnet",
      "properties": {
        "addressSpace": {
          "addressPrefixes": [
            "10.10.0.0/24",
            "10.20.0.0/24"
          ]
        },
        "subnets": [
          {
            "name": "master-subnet",
            "properties": {
              "addressPrefix": "10.10.0.0/24"
            }
          },
          {
            "name": "agent-subnet",
            "properties": {
              "addressPrefix": "10.20.0.0/24"
            }
          }
        ]
      },
      "type": "Microsoft.Network/virtualNetworks"
    }
  ]
}
```

If you want to try different subnet IP ranges, you can change the address prefixes in `aks-vnet.json` file.


## API Model

The API model file provides various configurations which aks-engine uses to create a cluster. We'll use `aks.json` api model file.

```json
{
  "apiVersion": "vlabs",
  "properties": {
    "orchestratorProfile": {
      "orchestratorType": "Kubernetes",
      "orchestratorRelease": "1.10",
      "kubernetesConfig": {
        "networkPlugin": "azure",
        "networkPolicy": "azure",
	      "apiServerConfig": {
          "--enable-admission-plugins": "NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota,AlwaysPullImages"
	      }
      }
    },
    "masterProfile": {
      "count": 1,
      "vmSize": "Standard_D2_v2"
    },
    "agentPoolProfiles": [
     {
        "name": "agentpool1",
        "count": 2,
        "vmSize": "Standard_D2_v2"
     }
    ],
    "linuxProfile": {
      "adminUsername": "azureadmin",
      "ssh": {
        "publicKeys": [
          {
            "keyData": ""
          }
        ]
      }
    },
    "servicePrincipalProfile": {
      "clientId":"",
      "secret": ""
    }
  }
}
```

* `keyData`: must contain the public portion of the SSH key we generated - this will be associated with the `adminUsername` value found in the same section of the cluster definition (e.g. 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABA....')
* `clientId`: this is the service principal's appId
* `secret`: this is the service principal's password


You should only provide `keyData`, `clientId` and `secret` fields in `aks.json` to be able to run the **build** script.

## Build Script
To build and deploy the kubernetes cluster on a custom Azure VNET, we'll use `build.sh` script. The script will:
- create the resource group on Azure,
- deploy a custom Azure VNET from `aks-vnet.json`,
- generate ARM templates,
- deploy kubernetes cluster on Azure,
- merge newly created kube config to the older,
- and, finally, print the `cluster-info`.

The `build.sh` script gets two parameters, environment (e.g.dev) and networking plugin that are supported by aks-engine.

There are 5 different Network Plugin options for aks-engine:

- Azure Container Networking (default)
- Kubenet
- Flannel
- Cilium
- Antrea

*HINT: In this document, we only explain the details of Kubenet and Azure-CNI networking options.*

A sample usage of the `build.sh` script is as follows:

```
$ sh build.sh dev azure
```

In following sections, we will create kubernetes clusters with different networking options in Azure.

# Networking Options of AKS-Engine

## Azure Container Networking

The default networking plugin of `aks-engine` is `azure` CNI. When we use Azure plugin, the pods get their own private IPs which are secondary IPs on the VMs’ NICs. Here pods aren’t exposed in the Virtual Network so there is no such private IPs.

To get a k8s cluster with azure CNI networking option, run the following command:
```
$ sh build.sh dev azure
```

(*When the execution ends, cluster info is printed on the command prompt.*)

Now, type the command below to get the IP addresses of the nodes on your cluster:
```
$ kubectl get nodes -o json | jq '.items[].status.addresses[].address'
```

*(If you did not already install `jq` on your computer, it can be downloaded from [here](https://stedolan.github.io/jq/download/))*

An output similar to the following should be given:
```
"k8s-agentpool1-37464322-vmss000000"
"10.20.0.4"
"k8s-agentpool1-37464322-vmss000001"
"10.20.0.35"
"k8s-master-37464322-0"
"10.10.0.5"
```

It's obvious that our nodes are getting IPs from the Azure VNET. Since the `azure` networking plug-in was used on the deployment, we're expecting that the `pods` also will get IP address from our custom Azure VNET. Let's check it out, by creating some pods.

Open `pod/ssh-pod-a-node-0.yaml` file in an editor and change `kubernetes.io/hostname` field with the name of your first agent node (The node with IP address **10.20.0.4**). In my case, it's `k8s-agentpool1-37464322-vmss000000`.

Deploy a sample pod on **node-0** with the following command:
```
$ kubectl apply -f pods/ssh-pod-a-node-0.yaml
```

Check the status of the pod with:
```
$ kubectl get pods -o wide
NAME               READY   STATUS    RESTARTS   AGE   IP           NODE
ssh-pod-a-node-0   1/1     Running   0          15m   10.20.0.31   k8s-agentpool1-37464322-vmss000000
```

We see that the IP of the pod is `10.20.0.31` and it's from our custom Azure VNET.

Let's check the connectivity between pods. Currently, we have a pod on **node-0**, deploy a new pod on **node-1** by executing the following command:
```
$ kubectl apply -f pods/ssh-pod-c-node-1.yaml
```

Run `kubectl get  pods -o wide` again to list the running pods:
```
NAME               READY   STATUS    RESTARTS   AGE   IP           NODE
ssh-pod-a-node-0   1/1     Running   0          20m   10.20.0.31   k8s-agentpool1-37464322-vmss000000
ssh-pod-c-node-1   1/1     Running   0          19s   10.20.0.43   k8s-agentpool1-37464322-vmss000001
```

The IP of the pod on **node-1** is `10.20.0.43`. Now, we can connect to first pod and try to **ping** second pod.
```
$ kubectl exec -it ssh-pod-a-node-0 -- bash
```

Run ping command to see the connectivity:
```
root@ssh-pod-a-node-0:/# ping 10.20.0.43
PING 10.20.0.43 (10.20.0.43) 56(84) bytes of data.
64 bytes from 10.20.0.43: icmp_seq=1 ttl=64 time=1.86 ms
64 bytes from 10.20.0.43: icmp_seq=2 ttl=64 time=0.630 ms
...
```

We're seeing that ICMP (ping) packages are successfully going from one pod to the another. Now, let's look into what is going on behind the scenes.

To copy your `ssh rsa` key into the pod on **node-0**, run the following command from your host.
```
$ kubectl cp ~/.ssh/ake_rsa ssh-pod-a-node-0:id_rsa
```

Connect to `pod-a` and check if the ssh rsa key copied correctly. Then, try to connect to the **agent** node-0.
```
$ kubectl exec -it ssh-pod-a-node-0 -- bash
root@ssh-pod-a-node-0:/# ls
bin   dev  home    lib	  media  opt   root  sbin  sys	usr
boot  etc  id_rsa  lib64  mnt	 proc  run   srv   tmp	var

root@ssh-pod-a-node-0:/# ssh -i id_rsa azureadmin@10.20.0.4
```

If everything went well, we're connected to **node-0**. You can list network interfaces of the node with `ifconfig` or `ip a` commands. When you execute these commands, you will see some interfaces whose names are beginning with `azv`. These NICs are the `veth` pipe pairs (a cable with two ends, whatever data that comes in one will come out of other and vice versa) of the pods we create on the **node-0**.

So, we need to find the `veth` pair of **pod-a** and listen that interface to see if ping packages arrive to it. To do that, first list running docker containers on the node.
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ docker ps
CONTAINER ID        IMAGE                                                  COMMAND                  CREATED             STATUS              PORTS               NAMES
4e4237e6912e        nginx                                                  "nginx -g 'daemon of…"   2 days ago          Up 2 days                               k8s_ssh-pod-a-node-0_ssh-pod-a-node-0_default_badd4f8e-369f-11e9-aeec-000d3a22d65a_0
c144e2deae85        k8s.gcr.io/pause-amd64:3.1                             "/pause"                 2 days ago          Up 2 days                               k8s_POD_ssh-pod-a-node-0_default_badd4f8e-369f-11e9-aeec-000d3a22d65a_0
```

Copy the `pause` container (a container which holds the network namespace for the pod.) name and change the following command accordingly.
```
$ docker inspect k8s_POD_ssh-pod-a-node-0_default_badd4f8e-369f-11e9-aeec-000d3a22d65a_0 | jq '.[].NetworkSettings.SandboxKey'
"/var/run/docker/netns/55568bb81358"
```

Run the command below after changing the namespace with the one that you got in the previous step.
```
[$ sudo nsenter --net=/var/run/docker/netns/55568bb81358 ip address](azureadmin@k8s-agentpool1-37464322-vmss000000:~$ sudo nsenter --net=/var/run/docker/netns/55568bb81358 ip address
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
16: eth0@if17: <BROADCAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 92:14:84:b5:9b:3c brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.20.0.31/24 scope global eth0
       valid_lft forever preferred_lft forever
)
```

The NIC name `eth0@if17` means that `eth0` interface of `pod-a` is paired with interface `17` in the **node-0**. So, let's look at the 17th NIC on the node.
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ ip a | grep 17
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
17: azv32fe06c7c68@if16: <BROADCAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master azure0 state UP group default qlen 1000
```

We have learnt that the `veth` pair on **node-0** side is `azv32fe06c7c68`. Now, let's send ping packages from **pod-a** and capture them on interface `azv32fe06c7c68`.

On a seperate tab, connect to **pod-a** and run the following:
```
root@ssh-pod-a-node-0:/# ping  10.20.0.43
PING 10.20.0.43 (10.20.0.43) 56(84) bytes of data.
64 bytes from 10.20.0.43: icmp_seq=1 ttl=64 time=3.38 ms
64 bytes from 10.20.0.43: icmp_seq=2 ttl=64 time=0.707 ms
...
```

And, on **node-0**, execute `tcpdump` command to see the icmp packages.
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ sudo tcpdump -i azv32fe06c7c68 icmp
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on azv32fe06c7c68, link-type EN10MB (Ethernet), capture size 262144 bytes
09:45:55.141131 IP 10.20.0.31 > 10.20.0.43: ICMP echo request, id 466, seq 42, length 64
09:45:55.141754 IP 10.20.0.43 > 10.20.0.31: ICMP echo reply, id 466, seq 42, length 64
...
```

All `veth` interfaces are bridged to `azure0` NIC. You can verify it with `brctl show` command. *(You can install it with `sudo apt install bridge-utils`)*
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ brctl show
bridge name	bridge id		STP enabled	interfaces
azure0		8000.000d3a21af12	no		azv04420ae93c6
							azv2c81fb847bd
							azv32fe06c7c68
							azv60b26fe7924
							azv7c82e9d3c90
							eth0
docker0		8000.0242fcd1dfa9	no
```

Now that the icmp packages coming from **pod-a** goes to `azure0` interface, let's capture the packets on it.
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ sudo tcpdump -i azure0 icmp
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on azure0, link-type EN10MB (Ethernet), capture size 262144 bytes
10:00:48.366965 IP 10.20.0.31 > 10.20.0.43: ICMP echo request, id 466, seq 924, length 64
10:00:48.368352 IP 10.20.0.43 > 10.20.0.31: ICMP echo reply, id 466, seq 924, length 64
```

Now, let's listen `eth0` interface of **pod-a** and see the ping packages.
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ sudo tcpdump -i eth0 icmp
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), capture size 262144 bytes
10:05:28.421475 IP 10.20.0.31 > 10.20.0.43: ICMP echo request, id 472, seq 1, length 64
10:05:28.422588 IP 10.20.0.43 > 10.20.0.31: ICMP echo reply, id 472, seq 1, length 64
```

That's it .. Since all the nodes and pods are directly connected to Azure VNET, there is no need any packet translation and all packets are send as is. Yo can see the connected NICs of `aks-vnet` on Azure Portal.


## Kubenet
Kubernetes default networking provider, kubenet, is a simple network plugin that works with various cloud providers. Kubenet is a very basic network provider, and basic is good, but does not have very many features. Moreover, kubenet has many limitations. For instance, when running kubenet in AWS Cloud, you are limited to 50 EC2 instances. Route tables are used to configure network traffic between Kubernetes nodes, and are limited to 50 entries per VPC.

To learn about the maximum number of routes you can add to a route table and the maximum number of user-defined route tables you can create per Azure subscription, see [Azure limits][2].

Let's create a kubernetes cluster with `kubenet` networking plug-in by running the below command.
```
$ sh build.sh dev kubenet
```

After execution finishes, `cluster info` of our kubernetes instance are printed to the screen. List the nodes with the command:
```
$ kubectl get nodes -o wide
NAME                                 STATUS   ROLES    AGE   VERSION    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
k8s-agentpool1-37464322-vmss000000   Ready    agent    16m   v1.10.12   <none>        Ubuntu 16.04.5 LTS   4.15.0-1036-azure   docker://3.0.1
k8s-agentpool1-37464322-vmss000001   Ready    agent    16m   v1.10.12   <none>        Ubuntu 16.04.5 LTS   4.15.0-1036-azure   docker://3.0.1
k8s-master-37464322-0                Ready    master   16m   v1.10.12   <none>        Ubuntu 16.04.5 LTS   4.15.0-1036-azure   docker://3.0.1
```

Let's continue by creating two seperate pods on each `agent` nodes. Before, we need to change the `node selector` field of the yaml files. Open `pod/ssh-pod-a-node-0.yaml` file in an editor and change `kubernetes.io/hostname` field with the name of your first agent node (The node with IP address **10.20.0.4**). In my case, it's `k8s-agentpool1-37464322-vmss000000`.

Now, deploy **pod-a** on **node-0** and **pod-c** on **node-1**.
```
$ kubectl apply -f pods/ssh-pod-a-node-0.yaml && kubectl apply -f pods/ssh-pod-c-node-1.yaml
pod/ssh-pod-a-node-0 created
pod/ssh-pod-c-node-1 created

$ kubectl get pods -o wide
NAME               READY   STATUS    RESTARTS   AGE   IP           NODE
ssh-pod-a-node-0   1/1     Running   0          47s   10.244.1.6   k8s-agentpool1-37464322-vmss000000
ssh-pod-c-node-1   1/1     Running   0          41s   10.244.0.7   k8s-agentpool1-37464322-vmss000001
```

Notice that the IPs of the pods aren't from Azure VNET, they are from `10.244.0.0/16` which is [default][3] for `kubenet` plug-in. If you open the `dev-aks-rg` resource group in Azure Portal, you would see a new resource type that we do not see in `azure cni` networking is the `Route Table`. For Kubernetes clusters with `kubenet` networking, we need to update the Azure VNET to attach to the route table. This is a known bug and is actually [documented][5].

Fortunately, we have associated the `route table` and `agent-subnet` in `build.sh` script. You can verify it by opening the route table in the Azure portal. You should see the **agent-subnet** in `Subnets` section of the route table.

Now, run the below command to send icmp packages from `pod-a` to `pod-c`.
```
$ kubectl exec -it ssh-pod-a-node-0 -- ping 10.244.0.7
PING 10.244.0.7 (10.244.0.7) 56(84) bytes of data.
64 bytes from 10.244.0.7: icmp_seq=1 ttl=62 time=1.43 ms
64 bytes from 10.244.0.7: icmp_seq=2 ttl=62 time=0.791 ms
64 bytes from 10.244.0.7: icmp_seq=3 ttl=62 time=0.733 ms
...
```

Let's connect to `node-0` and capture packets in NICs of the node.
```
$ kubectl cp ~/.ssh/ake_rsa ssh-pod-a-node-0:id_rsa
$ kubectl exec -it ssh-pod-a-node-0 -- bash
root@ssh-pod-a-node-0:/# ssh -i id_rsa azureadmin@10.20.0.4
```

If you list the networking interfaces of `node-0`, you should see a bunch of `veth` interfaces along with the others. We can find the `veth` pair of the `eht0` interface of `pod-a` in a similar way we did in `azure` cni section.
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ docker ps
CONTAINER ID        IMAGE                                                  COMMAND                  CREATED             STATUS              PORTS               NAMES
5e7a48217e87        nginx                                                  "nginx -g 'daemon of…"   About an hour ago   Up About an hour                        k8s_ssh-pod-a-node-0_ssh-pod-a-node-0_default_6a292568-38f1-11e9-b0fa-000d3a255d62_0
230a64c000be        k8s.gcr.io/pause-amd64:3.1                             "/pause"                 About an hour ago   Up About an hour                        k8s_POD_ssh-pod-a-node-0_default_6a292568-38f1-11e9-b0fa-000d3a255d62_0
...
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ docker inspect k8s_POD_ssh-pod-a-node-0_default_6a292568-38f1-11e9-b0fa-000d3a255d62_0  | jq '.[].NetworkSettings.SandboxKey'
"/var/run/docker/netns/ccfde56348fc"
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ sudo nsenter --net=/var/run/docker/netns/ccfde56348fc ip address
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
3: eth0@if10: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether b6:ed:2a:70:e5:04 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.244.1.6/24 scope global eth0
       valid_lft forever preferred_lft forever
```

From interface `eth0@if10`, we understand that NIC `eth0` of `pod-a` is paired with interface `10` in `node-0`. List the NICs of **node-0** to find the name of interface `10`.
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ ip a | grep 10
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    inet 10.20.0.4/24 brd 10.20.0.255 scope global eth0
3: enP1p0s2: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 1500 qdisc mq master eth0 state UP group default qlen 1000
5: cbr0: <BROADCAST,MULTICAST,PROMISC,UP,LOWER_UP> mtu 1500 qdisc htb state UP group default qlen 1000
    inet 10.244.1.1/24 scope global cbr0
10: veth923df63b@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master cbr0 state UP group default
```

Now, we can capture the packets in `veth923df63b` interface. When you run the tcpdump, you should get an output similar to the following:
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ sudo tcpdump -i veth923df63b icmp
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on veth923df63b, link-type EN10MB (Ethernet), capture size 262144 bytes
12:32:18.961826 IP 10.244.1.6 > 10.244.0.7: ICMP echo request, id 463, seq 1, length 64
12:32:18.962876 IP 10.244.0.7 > 10.244.1.6: ICMP echo reply, id 463, seq 1, length 64
...
```

This is good .. it means that we've found the right `veth` pair of the pod `pod-a`. To find the interface that is briged to `veth` NIC, we can run `brctl show` command.
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ brctl show
bridge name     bridge id               STP enabled     interfaces
cbr0            8000.a61b61df1786       no              veth2bbca7d4
                                                        veth3c3e12f3
                                                        veth7264149b
                                                        veth923df63b
                                                        vethc59025dd
docker0         8000.0242e1d44187       no
```

We can capture the ICMP packets in `cbr0` and `eth0` interfaces respectively.
```
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ sudo tcpdump -i cbr0 icmp
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on cbr0, link-type EN10MB (Ethernet), capture size 262144 bytes
12:40:24.871135 IP 10.244.1.6 > 10.244.0.7: ICMP echo request, id 468, seq 1, length 64
12:40:24.872458 IP 10.244.0.7 > 10.244.1.6: ICMP echo reply, id 468, seq 1, length 64
...
azureadmin@k8s-agentpool1-37464322-vmss000000:~$ sudo tcpdump -i eth0 icmp
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), capture size 262144 bytes
12:40:31.973569 IP 10.244.1.6 > 10.244.0.7: ICMP echo request, id 468, seq 8, length 64
12:40:31.974275 IP 10.244.0.7 > 10.244.1.6: ICMP echo reply, id 468, seq 8, length 64
```

This means that the ICMP (ping) packets get out of the node without any translation. So, how do packets know the right destination? The answer is Azure `route table`. If you open the route table in Azure Portal, you can see the rule that the packets destined to `10.244.0.0/24` are routed to node `10.20.0.5`.

# References
- AKS-Engine Quickstart Guide [[1]]
- Azure Networking Limits [[2]]
- Cluster Definitions [[3]]
- AKS Engine the Long Way [[4]]
- Attaching Cluster Route Table to VNET [[5]]

[1]:https://github.com/Azure/aks-engine/blob/master/docs/tutorials/quickstart.md
[2]:https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits?toc=%2fazure%2fvirtual-network%2ftoc.json#networking-limits
[3]:https://github.com/Azure/aks-engine/blob/master/docs/topics/clusterdefinitions.md#kubernetesconfig
[4]:https://github.com/Azure/aks-engine/blob/master/docs/tutorials/quickstart.md#aks-engine-the-long-way
[5]:https://github.com/Azure/aks-engine/blob/master/docs/tutorials/custom-vnet.md#post-deployment-attach-cluster-route-table-to-vnet