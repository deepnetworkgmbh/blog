---
layout: post
title: Kubelet API 
author: emrahkaya
categories: [kubernetes]
tags: [kubernetes, kubelet, metrics, monitoring]
---

In this post, we'll describe how a pod or a user can access the kubelet API available on each node of a kubernetes cluster to get information about pods (and more) on that node. We first discuss which ports are  available for this purpose, then list the available endpoints (resources) of the kubelet API. Lastly we discuss how to query the secure-port of and which authentication & authorization mechanisms are used.


* TOC
{:toc}

# Ports

kubelet gets a [long list of parameters](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/#options) at startup, most of which are deprecated and will be [set by using a kubelet configuration file](https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/) in upcoming releases. Either way, there are two parameters that relates to ports:

* --port (*port* in config file)
* --read-only-port (*readOnlyPort* in config file)

The *port* parameter specifies on which port the kubelet will listen to all requests securely (i.e. https). We'll refer to this port as **secure-port**. It's default value is **10250**.

The *read-only-port* parameter specifies on which port the kubelet will listen to some of the read-only (i.e. only GET) requests. We'll refer to this port as **read-only-port**. Not only the http methods, but also the endpoints exposed on this port are limited on this port (see [Endpoints](#Endpoints)). It's default value is **10255**.

Cloud kubernetes providers (like Azure AKS) generally leave those fields as default, so these ports will mostly be the same.

The default values for all ports can also be found [in the source code](https://github.com/kubernetes/kubernetes/blob/master/pkg/master/ports/ports.go).

# Endpoints

Although kubelet REST API is not documented, there some side documentation that mentions about the endpoints of kubelet:

* In the [Kubelet authentication/authorization](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet-authentication-authorization/) documentation, some endpoints are mentioned (/stats/, /metrics/, /logs/, /spec/) 

* The absence of a documented API is also an indication that the API is prone to change. So, the best (and only) place to fully see what resources are available is the [code of kubelet's server](https://github.com/kubernetes/kubernetes/blob/bd239d42e463bff7694c30c994abd54e4db78700/pkg/kubelet/server/server.go#L76-L84), which lists  endpoints as:

  * **/metrics**
  * **/metrics/cadvisor**
  * **/metrics/resource/*v1alpha1***
  * **/metrics/probes**
  * **/spec/**
  * **/stats/**
  * /logs/

  *The ones in bold are the endpoints available both for read-only-port and secure-port* 

* If you further [dig into the code](https://github.com/kubernetes/kubernetes/blob/bd239d42e463bff7694c30c994abd54e4db78700/pkg/kubelet/server/server.go#L284), you can see that there are some more endpoints:

  * **/pods**

* The [code also reveals](https://github.com/kubernetes/kubernetes/blob/bd239d42e463bff7694c30c994abd54e4db78700/pkg/kubelet/server/server.go#L353) that there are many debugging endpoints (The asterisk indicates there are route parameters to be defined like */portForward/{podNamespace}/{podID}*):

  * /configz (kubelet's configuration endpoint)
  * /run/*
  * /exec/*
  * /attach/*
  * /portForward/*
  * /containerLogs/*
  * /runningpods/
  * /cri/



## Read-Only-Port Endpoints

As mentioned above these endpoints are not only limited to read-only-port and secure-port also have these endpoints.

### /metrics

The endpoint for metrics related to kubelet's own statistics like 

* go_memstats_alloc_bytes

* http_request_duration_microseconds

* kubelet_cgroup_manager_latency_microseconds

* kubelet_container_log_filesystem_used_bytes

* kubelet_docker_operations_duration_seconds

* kubelet_runtime_operations_duration_seconds

* kubelet_volume_stats_used_bytes

* storage_operation_duration_seconds

  As the API is not documented and the kubelet is prone to change at any time; the best place to get current list of all metrics is basically running a GET request against your own kubelets (see [Authentication and Querying](#Authentication and Querying)). But you can find an example [here](/blog/assets/2020-01-13-kubelet-api/metrics endpoint.txt)

  

### /metrics/cadvisor

These include the most interesting metrics from a developer point of view. Because it provides the metrics for the pods and containers running at that node. Some of them are:

* container_cpu_load_average_10s
* container_cpu_usage_seconds_total
* container_fs_usage_bytes
* container_fs_write_seconds_total
* container_memory_usage_bytes
* container_memory_max_usage_bytes
* container_spec_cpu_quota
* machine_cpu_cores
* machine_memory_bytes

The current list can be found [here](/blog/assets/2020-01-13-kubelet-api/cadvisor.txt)



Those metrics are provided with helpful labels, thus allowing easy filtering on pod-name, container-name, namespace, etc.

For example the below metric provides CPU load average for the last 10 seconds for a specific container:

```
container_cpu_load_average_10s{
container="prometheus-config-reloader",
container_name="prometheus-config-reloader",
id="/kubepods/burstable/pod123456",
image="quay.io/coreos/prometheus-config-reloader@sha256:123456",
name="k8s_prometheus-config-reloader_prometheus-k8s-0_abcde",
namespace="mynamespace",
pod="prometheus-k8s-0",
pod_name="prometheus-k8s-0"} 
```

It's also interesting that metrics for some of the linux-system services are also served among these metrics:

```
container_cpu_load_average_10s{
container="",
container_name="",
id="/system.slice/networking.service",
image="", name="",namespace="",pod="",pod_name=""} 
```

Note that, such metrics have only *id* field set.



### /metrics/resource/*v1alpha1*

The resource endpoint requires a version. The current version is v1alpha1.

This endpoint lists resource (cpu & memory) usage metrics of containers and the node. So they are already included in the cadvisor endpoint. The metrics are:

* container_cpu_usage_seconds_total
* container_memory_working_set_bytes
* node_cpu_usage_seconds_total
* node_memory_working_set_bytes
* scrape_error (1 if there was an error while getting container metrics, 0 otherwise)



### /metrics/probes

This endpoint gives the liveness or readiness probe results for the pods in that node. It gives this results only for the pods that expose such an interface in its kubernetes deployment configuration.

The output is similar to this:

```
# HELP prober_probe_result The result of a liveness or readiness probe for a container.
# TYPE prober_probe_result gauge

prober_probe_result{ 
container="coredns",
container_name="coredns",
namespace="kube-system",
pod="coredns-1234567890-abcde",
pod_name="coredns-1234567890-abcde",
pod_uid="some uuid",
probe_type="Liveness"} 0

prober_probe_result{
container="prometheus",
container_name="prometheus",
namespace="monitoring",
pod="prometheus-12345",
pod_name="prometheus-12345",
pod_uid="some uuid",
probe_type="Liveness"} 0
```

### /spec/

This gives the specifications of the node; like cpu frequency, cpu core count, memory capacity, filesystems, network devices, etc. The output is in JSON format.

### /stats/

This gives some statistical information for the resources in the node in JSON format. The resources include not only cpu & memory but also disks, network interfaces and processes.

### /pods

This gives information for the pods deployed to the node. The information is very detailed and includes the metadata, labels, annotations, owner references (for example the DaemonSet that owns the pod), volumes, containers, and status.

You can find the structure of a pod entry [here](/blog/assets/2020-01-13-kubelet-api/pods_entry.txt).



## Secure-Port Endpoints

Note: For the examples in this section we'll use the notation discussed in the [Secure Port](#Secure Port) section. The examples are written for being run from inside a pod in that node. If you like to run them without deploying a pod, follow the steps in [Accessing from outside](#Accessing from outside) section.

Additionally, as many users tend to use a cloud-based kubernetes solution, which generally lacks of [Token-based authentication](#Token-based authentication) and uses [Certificate-based authentication](#Certificate-based authentication) for `kubelet` , the examples are using `/proxy/xxx`,  which supports tokens.

### /logs/

The logs endpoint itself doesn't expose logs directly but rather includes many subresources. If you run

```bash
curl -k --header "Authorization: Bearer $TOKEN"  https://kubernetes/api/v1/nodes/$NODE_NAME/proxy/logs/
```

it will return many links to logs on the system:

```html
<pre>
<a href="alternatives.log">alternatives.log</a>
<a href="alternatives.log.1">alternatives.log.1</a>
<a href="apt/">apt/</a>
<a href="auth.log">auth.log</a>
<a href="auth.log.1">auth.log.1</a>
<a href="auth.log.2.gz">auth.log.2.gz</a>
...
```

which can be queried individually: 

```bash
curl -k --header "Authorization: Bearer $TOKEN"  https://kubernetes/api/v1/nodes/$NODE_NAME/proxy/logs/auth.log
```



### /configz

This basically returns the kubelet's configuration in JSON format. This endpoint supports only GET, but as it includes some private information, it's accessible via only secure-port.



### /containerLogs/

This is a namespaced-endpoint, i.e. it requires to have container's namespace defined in the request route. You can query individual container's logs by querying `/containerLogs/{podNamespace}/{podID}/{containerName}`. For example:

```bash
curl -k --header "Authorization: Bearer $TOKEN"  https://kubernetes/api/v1/nodes/$NODE_NAME/proxy/containerLogs/kube-system/coredns-1234567890-abcde/coredns
```



### /runningpods/

This endpoint returns a PodList json, which includes the metadata and spec definitions for all the pods on that node.

```bash
curl -k --header "Authorization: Bearer $TOKEN"  https://kubernetes/api/v1/nodes/$NODE_NAME/proxy/runningpods/
```

gives

```json
{
    "kind": "PodList",
    "apiVersion": "v1",
    "metadata": {},
    "items": [
        {
            "metadata": {
                "name": "kube-proxy-12345",
                "namespace": "kube-system",
                "uid": "",
                "creationTimestamp": null
            },
            "spec": {
                "containers": [
                    {
                        "name": "kube-proxy",
                        "image": "sha256:123",
                        "resources": {}
                    }
                ]
            },
            "status": {}
        },
...
```



### /run/, /exec/, /attach/, /portForward/, /cri/

These endpoints are used by kubernetes to manage the node, pods and containers. These have many options and are out of scope of this documentation. 



# Authentication and Querying

## Read-Only Port

A pod running on a node can query the read-only port (over http) on that node without any further requirement. This gives a convenient way to get metrics on a specific node. If there are no custom settings you've made for pod or node network isolation, a pod can also query other nodes on the same cluster.

So, before going into a programmatic approach, you can just run /bin/sh (or /bin/bash) on any suitable pod on the target node, and query the cadvisor metrics using curl or wget:

```bash
curl http://<NODE NAME or NODE IP>:10255/metrics/cadvisor
```

which will return the pre-mentioned cadvisor metrics as the body of the response.

By using this capability, one can create his own DaemonSet (let's call it `metrics-proxy`) and apply filtering on the kubelet metrics for the use of Prometheus. Prometheus can be configured to scrape metrics from `metrics-proxy`, and `metrics-proxy` can add new metrics as well as filter out some metrics provided by the kubelet. For example, it can filter out metrics from other namespaces other than the requested one.

## Secure Port

Accessing the secure port requires authenticating & authorizing against the API Server of the cluster. Thus, you'll need to use the credentials of a valid user or service account while querying the secure port over https.

### Required ClusterRoleBinding

Fortunately, the kubernetes documentation includes [a page for the authentication of the kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet-authentication-authorization/). It lists the kubelet API resources and the requested privileges for that resource. In fact, all kubelet API resources is controlled by the `node` resource. For example, if you like to query (http GET) `/metrics` endpoint (resource) of kubelet, then the service account of the pod is required to have `nodes/metrics` given `get` privilege.

This can be done by creating a `ClusterRoleBinding` to the service account the pod uses. There's already a suitable ClusterRole for binding for this purpose, ` system:kubelet-api-admin`. In fact, it has more privileges than needed for just querying metrics:

```yaml
rules:
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - proxy
- apiGroups:
  - ""
  resources:
  - nodes/log
  - nodes/metrics
  - nodes/proxy
  - nodes/spec
  - nodes/stats
  verbs:
  - '*'
```

As you can see, the verbs for `node` resources are `*` . So, it might be better to create our own limited `ClusterRole`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: mymonitoring-clusterrole
  namespace: default
rules:
- apiGroups: [""]
  resources:
  - nodes/log
  - nodes/metrics
  - nodes/proxy
  - nodes/spec
  - nodes/stats
  verbs:
  - 'get'
```



Once you have the `ClusterRole`, you can bind it to your service account, via a `ClusterRoleBinding` definition:

```yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: mymonitoring-clusterrole-binding
roleRef:
  kind: ClusterRole
  name: mymonitoring-clusterrole
  apiGroup: "rbac.authorization.k8s.io"
subjects:
- kind: ServiceAccount
  name: mymonitoring
  namespace: default
```



### Using Service Account Credentials

Once you've setup the service account and its cluster role binding, you can use it in the Pod for querying against kubelet. Let's assume we have deployed this Pod to our cluster:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mymonitoring-ubuntu
  namespace: default
spec:
  serviceAccountName: mymonitoring
  containers:
  - name: mymonitoring-ubuntu
    image: ubuntu:18.04
    command:
    - /bin/bash
    - -c
    - "sleep 1000000"
    env:
      - name: NODE_NAME
        valueFrom:
          fieldRef:
            fieldPath: spec.nodeName
```

Here you can see we've specified the service account and also supplied the NODE_NAME which will be useful later. Once you deploy this and `exec` into it (`kubectl exec -it mymonitoring-ubuntu -- bin/bash`)  you can get the access token for the `mymonitoring` account by reading the contents of the `/var/run/secrets/kubernetes.io/serviceaccount/token` file:

```bash
TOKEN=cat /var/run/secrets/kubernetes.io/serviceaccount/token
```

Then you can install `curl` and run this command to get metrics from `/metrics` endpoint of the `kubelet`:

```bash
curl -k --header "Authorization: Bearer $TOKEN"  https://$NODE_NAME:10250/metrics
```

At this point you may also get an "Unauthorized" response, which indicates the cluster setup is not (easily) suitable for this method (Details below) . At that point you can access the same metrics using the `/proxy` endpoint of the Kubernetes' API Server:

```bash
curl -k --header "Authorization: Bearer $TOKEN"  https://kubernetes/api/v1/nodes/$NODE_NAME/proxy/metrics
```

Please note that, this is possible because we've included `nodes/proxy` in the allowed resources of our `ClusterRole` definition.

### Accessing from outside

If you like to access kubelet endpoints without deploying a pod, you can directly talk with Kubernetes API Server, once you get the credentials for the privileged service account.

Firstly, create the service account and give privilege to it by binding the ClusterRole, as mentioned in the [Required ClusterRoleBinding](#Required ClusterRoleBinding) section.

Then, get its secret token:

```bash
SERVICE_ACCOUNT=<the service account name>

SECRET=$(kubectl get serviceaccount ${SERVICE_ACCOUNT} -o json | jq -Mr '.secrets[].name | select(contains("token"))')

TOKEN=$(kubectl get secret ${SECRET} -o json | jq -Mr '.data.token' | base64 -d)
```

Please note that, kubectl returns a base64-encoded version of the token, so we decode it before use.

Next step is to get the address of your cluster's API Server:

```bash
APISERVER=$(kubectl config view | grep server | cut -f 2- -d ":" | tr -d " ")
```

Please note that, if you have several clusters in your `~/.kube/config` file the above command may not work. Then simply run the `kubectl config view | grep server | cut -f 2- -d ":" | tr -d " "` command and assign one of the suitable API servers' address to `APISERVER` manually.

Last step is to select the node, which can be done by running a `kubectl get nodes` command and assigning the desired node's name to `NODE` variable.

Once you've setup those steps you can run requests against the API Server similarly:

```bash
curl -k -H "Authorization: Bearer $TOKEN" $APISERVER/api/v1/nodes/$NODE/proxy/metrics/cadvisor
```



### Kubelet Authentication and Authorization Mechanism

For the authentication part, there are three ways to have access to kubelet API:

#### **Anonymous Authentication** 

This option is available only if the kubelet had been started with `--anonymous-auth=false` flag

#### **Certificate Based Authentication**

You can use X509 client certificate authentication with kubelet, if:

- the kubelet had been started with the `--client-ca-file` flag, (ex. `--client-ca-file=/etc/kubernetes/certs/ca.crt`) providing a CA bundle to verify client certificates with. 

- The kubernetes API Server shad been started with `--kubelet-client-certificate` and `--kubelet-client-key` flags

  That means you'll need to have certificates signed with the given `ca.crt` Certificate Authority file (and it's counter-part `ca.key`).
  If you're running your own cluster, you'll create and pass these files easily, but for cloud-managed clusters (like Azure Kubernetes Service (AKS)), the certificate (the `ca.key` part, indeed) passed to the apiserver is not available to the user. Because, the file is created by AKS and the master node is not accessible. In this case, you might want to use the `/proxy` endpoint to redirect the same requests to the `kubelet` having API Server in the middle, which generally supports Token based authentication.

#### **Token Based Authentication**

For most cases token based authentication is the way to go. To be able to use service account token for the kubelet, there are some pre-conditions to be met for API Server authentication and authorization, which are listed in the [Kubelet documentation](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet-authentication-authorization/#kubelet-authentication) mentioned above.

It says that:

> - ensure the `authentication.k8s.io/v1beta1` API group is enabled in the API server
> - start the kubelet with the `--authentication-token-webhook` and `--kubeconfig` flags

For the cloud-provided cluster solutions (for ex. Azure AKS), first item is always met. You can check whether it's available or not by running `kubectl get apiservice` , which should return a response that includes:

```bash
v1beta1.authentication.k8s.io          Local                        True
```

However, the second requirement may not be met. You can check it by either running a `ps aux | grep kubelet` command from a privileged pod or (better) run 

```bash
curl -k --header "Authorization: Bearer $TOKEN"  https://kubernetes/api/v1/nodes/$NODE_NAME/proxy/configz
```

which will return the kubelet configuration. It includes these parts:

```json
"authentication": {
    "x509": {
        "clientCAFile": "/etc/kubernetes/certs/ca.crt"
    },
    "webhook": {
        "enabled": false,
        "cacheTTL": "2m0s"
    },
    "anonymous": {
        "enabled": false
    }
},
"authorization": {
    "mode": "Webhook",
    "webhook": {
        "cacheAuthorizedTTL": "5m0s",
        "cacheUnauthorizedTTL": "30s"
    }
},

```

You can see that anonymous access is already disabled and webhook authentication is disabled, as well. The only way to authenticate against the kubelet is using certificates.

But let's assume that we're utilizing out own-managed cluster and have the Token based authentication for kubelet enabled. Then, we'll basically pass the same Authorization bearer token as a header parameter with our request (`--header "Authorization: Bearer $TOKEN"`). It'll be used for both authentication and authorization against the kubelet.



For the authorization part, similar conditions exist. From the  [Kubelet documentation](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet-authentication-authorization/#kubelet-authentication):

> - ensure the `authorization.k8s.io/v1beta1` API group is enabled in the API server
> - start the kubelet with the `--authorization-mode=Webhook` and the `--kubeconfig` flags

Both can be checked similar to the authentication discussed above. The above kubelet configuration shows that the cloud-provided cluster (AKS) is setup correctly to use Webhooks.
