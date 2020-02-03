---
layout: post
title: How to Setup an ELK Stack and Filebeat on Kubernetes 
author: haktas
---

The logs are one of the most critical parts of every infrastructure for monitoring and debugging purposes. In general, there are different types of logs in every infrastructure including third-party, system, application specific logs which have different log formats like `json`, `syslog`, `text`, etc. It is not trivial to handle all these different log formats. But the main challenge is not only the variety of formats but also lots of log producers, especially in cluster environments. It is not possible to perform collection and processing manually. So, to be able to overcome these challenges, you have to utilize the well-known, dedicated tools and frameworks such as [ELK Stack](https://www.elastic.co/what-is/elk-stack), [Filebeat](https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-overview.html).

## What is ELK Stack and Filebeat

It is an acronym for three open source projects: `Elasticsearch`, `Logstash` and `Kibana`. Elasticsearch is a real-time, distributed, and scalable search and analytics engine. Logstash is a server‑side data processing pipeline that ingests data from multiple sources simultaneously, transforms it, and then sends it to a stash like Elasticsearch. Kibana lets users visualize data with charts and graphs in Elasticsearch. Filebeat is a lightweight shipper for forwarding and centralizing log data. Installed as an agent on your servers. It monitors the log files or locations that you specify, collects log events, and forwards them to either to `Elasticsearch` or `Logstash` for indexing. In our blog post, we are going to deploy filebeat as a DaemonSet and forward logs to Logstash.

Before diving into details, if you want to know why we are deploying elasticsearch to the k8s, you can read [this article](https://sematext.com/blog/kubernetes-elasticsearch/).  

## Prerequisites

- Running aks cluster and kubectl.
- Deployments will be performed via `helm` k8s package manager. Also, our sample aks cluster is an rbac enabled. Otherwise, you can skip the next section. If you are not sure whether your cluster is rbac enabled or not, please follow [this](https://stackoverflow.com/questions/51238988/how-to-check-whether-rbac-is-enabled-using-kubectl).
So, before using helm, we need to give necessary permissions to the helm server side component named Tiller to create k8s resources in all the namespaces. 
- In fact, there man ways deploying elastic stack to k8s for example by official helm chart or [Elastic Cloud on k8s](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-quickstart.html) which is pretty easy to install. But in this post, we are going to deploy our stack manually to get better understanding.

### Enable helm on RBAC enabled AKS Cluster

- Create service account tiller for the Tiller server in the kube-system namespace
- Bind the cluster-admin role to this Service Account. Since we want Tiller to manage resources in all namespaces, we will use [ClusterRoleBinding](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- You can create both of them by using kubectl with separate commands. Also, you can put the resource definitions in a manifest file (for example helm-rbac.yml) and perform kubectl apply command like in the following:

``` yml
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: tiller
    namespace: kube-system
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: tiller
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: cluster-admin
  subjects:
    - kind: ServiceAccount
      name: tiller
      namespace: kube-system
```

``` yml
  kubectl apply -f helm-rbac.yml
```

 - Now you can setup Tiller to your rbac enabled cluster with the created service account with the following command:

 ``` yml
  helm init --service-account tiller --upgrade --wait
 ```

## Deploy Elasticsearch

Deployments in k8s do not keep state in their Pods by assuming the application is stateless. Since Elasticsearch maintains state, we need to use `StatefulSet` which is a deployment that can maintain state. StatefulSets will ensure the same `PersistentVolumeClaim` stays bound to the same Pod throughout its lifetime. Unlike a Deployment which ensures the group of Pods within the Deployment stay bound to a `PersistentVolumeClaim`. Other than these, we need a [Headless Service](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) which is used for discovery of StatefulSet Pods.


## Summary

In this blog, we have seen how `Managed Service Identities` can be used to connect to `Azure SQL Database` without manually handling credentials, in cluster level with the help of `aad-pod-identity-binding`.