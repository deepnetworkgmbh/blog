---
layout: post
title: Password Protected EFK Stack on Kubernetes
author: onuryilmaz
---

In this article, my aim is to play around with EFK stack on Kubernetes which is a collection of [Elasticsearch]https://www.elastic.co/elasticsearch/, [Fluentd]https://www.fluentd.org and [Kibana]https://www.elastic.co/kibana/. The main motivation behind that stack is reliably and securely take the data from the k8s cluster, in any format, then search, analyze and visualize it any time. In brief,

- **Elasticsearch** is a distributed, open source search and analytics engine for all types of data, including textual, numerical, geospatial, structured, and unstructured.
- **Fluentd** is an open source data collector, which lets you unify the data collection and consumption for a better use and understanding of data.
- **Kibana** is an open source frontend application providing search and data visualization capabilities for data indexed in Elasticsearch.

I always prefer minikube for such experimental works, which makes easy to run k8s locally. Please note that minikube uses 1GB of memory and 2 CPU cores by default and these values are not sufficient for our EFK stack. You should start/configure minikube with the following command:

``` yml
$ minikube start --memory 8192 --cpus 4
```

If you have installed minikube successfully and run it with above configuration, you're about halfway through the EFK stack :)

---

To get started, create a namespace inside minikube, to do that you can simply run the following command:

``` yml
$ kubectl create ns kube-logging
```

A minor detail, you're going to find a file inside each module named as _kustomization.yaml_, [kustomize]https://kustomize.io is another facilitator which lets us customize raw, template-free YAML files for multiple purposes, leaving the original YAML untouched and usable as is.

***

## Elasticsearch

Let's get started to walk through the details of Elasticsearch which consists of a Statefulset, service, persistent volume and ConfigMap. You can always have a quick look to get the component summary from its _kustomization.yaml_ file.
Firstly, we will claim a persistent volume from k8s for our Elasticsearch Statefulset which will be used to store the data collected by Fluentd.

Firstly, we will claim a persistent volume from k8s for our Elasticsearch Statefulset which will be used to store the data collected by Fluentd.

``` yml
resources:
- statefulset.yaml
- service.yaml
- configmap.yaml
- pvc.yaml
```

Secondly, we will deploy a service to expose our Elasticsearch application running on a set of pods as a network service, and all components running in our cluster would be able to reach Elasticsearch through port 9200.

``` yml
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  labels:
    component: elasticsearch
spec:
  type: NodePort
  selector:
    component: elasticsearch
  ports:
  - port: 9200
    targetPort: 9200
```

Then, our Elasticsearch application will be deployed as Statefulset with the following configuration. More importantly, we will create a user immediately after the container started, which will be used in Kibana and Fluentd to access Elasticsearch.

``` yml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
spec:
  serviceName: elasticsearch
  replicas: 1
  selector:
    matchLabels:
      component: elasticsearch
  template:
    metadata:
      labels:
        component: elasticsearch
    spec:
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:6.8.6
        imagePullPolicy: IfNotPresent
        # Add post start lifecycle to add elasticsearch user
        lifecycle:
          postStart:
           exec:
            command: ["/bin/sh", "-c", "/usr/share/elasticsearch/bin/elasticsearch-users useradd esUser -p esPassword -r superuser"]
        env:
        - name: discovery.type
          value: single-node
        ports:
        - containerPort: 9200
          name: http
          protocol: TCP
        volumeMounts:
        - name: elasticsearch-config
          mountPath: /usr/share/elasticsearch/config/elasticsearch.yml
          subPath: elasticsearch.yml
        - name: elasticsearch-data
          mountPath: /usr/share/elasticsearch/data
        resources:
          limits:
            cpu: 500m
            memory: 4Gi
          requests:
            cpu: 500m
            memory: 4Gi
      # Allow non-root user to access PersistentVolume
      securityContext:
        fsGroup: 1000
      restartPolicy: Always
      volumes:
      - name: elasticsearch-config
        configMap:
          name: elasticsearch-config
      - name: elasticsearch-data
        persistentVolumeClaim:
          claimName: elasticsearch-pvc
```

Lastly, we will configure Elasticsearch via a ConfigMap. Please make sure that xpack license configured as basic and security feature enabled in elasticsearch.yaml file. I suggest to disable unnecessary xpack features like machine learning, watcher, etc. to reduce the Elasticsearch load on our cluster.

``` yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: elasticsearch-config
  labels:
    component: elasticsearch
data:
  elasticsearch.yml: |
    cluster.name: password-protected-efk
    node.name: node-1
    path.data: /usr/share/elasticsearch/data
    http:
      host: 0.0.0.0
      port: 9200
    bootstrap.memory_lock: true
    transport.host: 127.0.0.1
    xpack.license.self_generated.type: basic
    # Enable xpack.security which is provided in basic subscription
    xpack.security.enabled: true
    # Disable unused xpack features 
    xpack.monitoring.enabled: false
    xpack.graph.enabled: false
    xpack.watcher.enabled: false
    xpack.ml.enabled: false
```

You can verify your Elasticsearch deployment with the following command:

``` yml
$ kubectl port-forward statefulsets/elasticsearch 9200:9200 -n kube-logging

$ curl http://esUser:esPassword@localhost:9200
{
  "name" : "node-1",
  "cluster_name" : "password-protected-es",
  "cluster_uuid" : "drCrVHW6QaS9szl5olpO3Q",
  "version" : {
    "number" : "6.8.6",
    "build_flavor" : "default",
    "build_type" : "docker",
    "build_hash" : "3d9f765",
    "build_date" : "2019-12-13T17:11:52.013738Z",
    "build_snapshot" : false,
    "lucene_version" : "7.7.2",
    "minimum_wire_compatibility_version" : "5.6.0",
    "minimum_index_compatibility_version" : "5.0.0"
  },
  "tagline" : "You Know, for Search"
}
```

***

## Kibana

We'll continue with Kibana deployment, if you've done with Elasticsearch. Our Kibana setup contains a Deployment, Service and ConfigMap like we do in Elasticsearch.

``` yml
resources:
- deployment.yaml
- service.yaml
- configmap.yaml
```

First of all, as we do for the Elasticsearch, a NodePort service is required to expose the service port 5601 on each node's IP at a static port. A cluster IP service is created automatically, and the node port service will route to it. Afterwards, you'll be able to reach Kibana application through port 5601.

``` yml
apiVersion: v1
kind: Service
metadata:
  name: kibana
  labels:
    component: kibana
spec:
  type: NodePort
  selector:
    component: kibana
  ports:
  - port: 5601
    targetPort: 5601
```

Then, we'll define a deployment object for our Kibana application, I don't need any scaling mechanism for this PoC but you can of course adjust replica count w.r.t. the requirement and have identical multiple Kibana pods handle your workload. As you can easily notice, it is important to give **ELASTICSEARCH_URL**, **XPACK_SECURITY_ENABLED**, **ELASTICSEARCH_USERNAME** and **ELASTICSEARCH_PASSWORD** environment variables to Kibana deployment.

``` yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
spec:
  selector:
    matchLabels:
      component: kibana
  template:
    metadata:
      labels:
        component: kibana
    spec:
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:6.5.4
        env:
        - name: ELASTICSEARCH_URL
          value: http://elasticsearch:9200
        - name: XPACK_SECURITY_ENABLED
          value: "true"
        - name: ELASTICSEARCH_USERNAME
          valueFrom:
            configMapKeyRef:
              name: kibana-config
              key: elasticsearch_username
        - name: ELASTICSEARCH_PASSWORD
          valueFrom:
            configMapKeyRef:
              name: kibana-config
              key: elasticsearch_password
        envFrom:
        - configMapRef:
            name: kibana-config
        ports:
        - containerPort: 5601
          name: http
          protocol: TCP
```

Finally, you need to configure your Kibana deployment via a ConfigMap so that Kibana application would be able to access the content indexed on the Elasticsearch cluster.

``` yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kibana-config
  labels:
    component: kibana
data:
  elasticsearch_username: esUser
  elasticsearch_password: esPassword
```

Now, you can verify your Elasticsearch/Kibana deployment at your browser with the following url:

``` yml
$ kubectl get svc -n kube-logging

NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
elasticsearch   NodePort   10.101.45.171   <none>        9200:32359/TCP   20m
kibana          NodePort   10.96.211.1     <none>        5601:30071/TCP   20m

$ echo http://$(minikube ip):KIBANA_EXPOSED_PORT

http://192.168.64.16:30071
```

***

## Fluentd

In the previous parts, we experienced how to deploy Elasticsearch and Kibana on k8s. Now, in the last part of this article, we'll be concentrating on Fluentd deployment which composed of a ConfigMap, Daemonset and Role-Based-Access-Control(RBAC) configuration.

``` yml
resources:
- daemonset.yaml
- rbac.yaml
- configmap.yaml
```

At first, we'll authorize our Fluentd application to get/list/watch pods and namespaces inside our k8s cluster. As namespaces are cluster-scoped objects we need to create a ClusterRole while regulating access to them. By this way, our data collector would gain read-only access to the pods and namespaces inside cluster.

``` yml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluentd
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: fluentd
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - namespaces
  verbs:
  - get
  - list
  - watch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: fluentd
roleRef:
  kind: ClusterRole
  name: fluentd
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: fluentd
```

Thereafter, our Fluentd data collector application will be deployed as Daemonset so that we'll ensure that all nodes inside our cluster run a copy of Fluentd pod.

``` yml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  labels:
    component: fluentd
    kubernetes.io/cluster-service: "true"
spec:
  selector:
    matchLabels:
      component: fluentd
  template:
    metadata:
      labels:
        component: fluentd
        kubernetes.io/cluster-service: "true"
    spec:
      serviceAccount: fluentd
      serviceAccountName: fluentd
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1.3-debian-elasticsearch
        env:
          - name:  FLUENT_ELASTICSEARCH_HOST
            value: "elasticsearch.kube-logging"
          - name:  FLUENT_ELASTICSEARCH_PORT
            value: "9200"
          - name: FLUENT_ELASTICSEARCH_SCHEME
            value: "http"
          - name: FLUENT_UID
            value: "0"
          - name: FLUENT_ELASTICSEARCH_USER
            valueFrom:
              configMapKeyRef:
                name: fluentd-config
                key: elasticsearch_username
          - name: FLUENT_ELASTICSEARCH_PASSWORD
            valueFrom:
              configMapKeyRef:
                name: fluentd-config
                key: elasticsearch_password
        envFrom:
        - configMapRef:
            name: fluentd-config
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      terminationGracePeriodSeconds: 30
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

As we did in the previous components, Fluentd application requires the credentials to store  the collected data in Elasticsearch cluster reliably and safely. It is crucial to state that you must change namespace value in **FLUENT_ELASTICSEARCH_HOST** environment variable with your namespace name if you've chose another.

``` yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  labels:
    component: fluentd
data:
  elasticsearch_username: esUser
  elasticsearch_password: esPassword
```

Now, it's time to verify that our freshly deployed EFK stack works as expected or not. Please, navigate Kibana endpoint again  and try to create an index pattern by selecting the _logstash_ index which is newly created by Fluentd. You should be able to view your application logs under _Discover_ page.

***

## Final Words

To sum up, I tried to express how a password protected EFK stack could be deployed to the Kubernetes cluster by using xpack features. Hope you find what you were looking for and I made myself clear. Please don't hesitate to [connect]https://www.linkedin.com/in/onrylmz/ / contact via onur.yilmaz[at]deepnetwork.com.
