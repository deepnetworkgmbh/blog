---
layout: post
title: Some notes on Kubernetes Networking
---

This is basically a summary of "Kubernetes Networking" chapter in "Container Networking: From Docker to Kubernetes", as well as some relevant notes, investigations, and articles. The book is available [here](https://www.nginx.com/resources/library/container-networking-docker-kubernetes/) for free.

---

Kubernetes requires the following from the networking setup, the rest is up to you:

* Containers can communicate with all other containers without NAT. 
* Nodes can communicate with all containers (and vice versa) without NAT. 
* The IP a container sees itself is the same IP as others see it. 

There are 3 types of communication that can happen on the network layer:
	1. container to container within a pod
	2. pod to pod
	3. to/from the cluster

#1
The `infrastructure container` or rather `pause container` is responsible of namespace sharing, including network, between containers within a `pod`. Therefore, all containers are on the same host and share the same IP. There is a good article [here](https://www.ianlewis.org/en/almighty-pause-container) that goes into details of this special container.

#2
Every `pod` gets its own IP (that containers within that pod shares among each other as explained above) on the same network. A pod can talk to another pod directly without worrying about NAT. A detailed article on this is available [here](https://medium.com/google-cloud/understanding-kubernetes-networking-pods-7117dd28727) It is important to realise that your `pods` sit a different network than your `nodes` which is built on the `node` network.

Your `service` objects on the hand get a virtual IP which can be used to avoid dealing with `pod` IPs that might be changing as the `pods` get destroyed and created. These virtual IPs however exist only on the Kubernetes realm and are not real IPs on the network stack. 

Let's examine a real case:
* We have an `nginx` `statefulset` with 2 instances.
	* `pod` 1 IP: `10.240.0.53`
	* `pod` 2 IP: `10.240.0.28`
* We have an `nginx` `service` that maps these two instances
	* `service` IP: `10.0.33.45`
* We have two nodes, each hosting one of the pods

In one of the nodes, if we examine the `iptables` rules this is what we see the following lines:

1. _jump_ to `KUBE-SVC-YK2SNH4V42VSDWIJ` for anything that targets the service IP.
```
-A KUBE-SERVICES -d 10.0.33.45/32 -p tcp -m comment --comment "default/nginx:web cluster IP" -m tcp --dport 80 -j KUBE-SVC-YK2SNH4V42VSDWIJ
```

2. Load balance the requests. Send half of them to `KUBE-SEP-B4KBD76YHXMJL4VO` and other half to `KUBE-SEP-V73B5NNFXA6V3U7A`.
```
-A KUBE-SVC-YK2SNH4V42VSDWIJ -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-B4KBD76YHXMJL4VO
-A KUBE-SVC-YK2SNH4V42VSDWIJ -j KUBE-SEP-V73B5NNFXA6V3U7A
```

3. Send `KUBE-SEP-B4KBD76YHXMJL4VO` to IP of Pod 1, and send `KUBE-SEP-V73B5NNFXA6V3U7A` to IP of Pod 2.
```
-A KUBE-SEP-B4KBD76YHXMJL4VO -p tcp -m tcp -j DNAT --to-destination 10.240.0.28:80
-A KUBE-SEP-V73B5NNFXA6V3U7A -p tcp -m tcp -j DNAT --to-destination 10.240.0.57:80
```




