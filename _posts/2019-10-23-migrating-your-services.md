---
layout: post
title: Migrating your services to another cluster
---

Let’s examine how to shutdown a _service_ gracefully in Kubernetes and migrate it to a different cluster. Here the term _service_ is used liberally and doesn’t refer to a Kubernetes `Service` object. Your _service_ will probably be composed of one or more Kubernetes objects, including a `Service` object as well as `Deployment`, `Pod`, `StatefulSet`, `PersistentVolumeClaim`, `PersistentVolume` etc. 

Table of Contents:

- Shutting a service down
	- Preserving storage
	- Shutting processes gracefully
		- preStep Hook
		- Handling `SIGTERM`
- Carry over your services
	- Binding to an existing storage resource
	- Picking up an existing persistent volume from your service
	
## Shutting a service down
We need to ensure two things when shutting down a service:

* Any storage resource mounted to your service is preserved.
* Your service processes are shutdown gracefully.

This will allow us to carry our service elsewhere, take our data with it, deploy and continue from where we left.

### Preserving Storage
There is a simple way to ensure a storage resource in your cloud provider is preserved when you delete a Kubernetes object that created this resource. You need to set `persistentVolumeReclaimPolicy` on the associated `PersistentVolume` to `Retain`

To see all the `PersistentVolume` objects’ retain policy in the `default` namespace you can execute `kubectl get pv`.

For each persistent volume, you can run the following command to update their policy to `Retain`:

```
kubectl patch pv <your-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

After this, deleting the `PersistentVolume` itself or deleting the Kubernetes object that created the `PersistentVolume` via a claim will preserve the underlying resource (e.g. Azure Disk, Azure File etc)

### Shutting processes gracefully
Once you take care of your storage, you need to shutdown your containers, or to be more specific, processes running in your containers, _gracefully_.

Kubernetes will follow the below path once a `Pod` is  _deleted_:

1. Pod state is set to `Terminating`
2. preStep Hook is executed in the container.
3. `SIGTERM` is sent to all containers. To be more precise, this will lead to docker sending `SIGTERM` to the process with `PID` 1 running in your containers.
4. Kubernetes will wait for a grace period
5. `SIGKILL` is sent to containers that are still running

The goal is basically to avoid step #5 where some of your processes are killed and you risk having corrupt data in your storage.

Steps 2 to 3 is where we can do something to avoid step 5.

#### preStep Hook
If your containers cannot deal with `SIGTERM` for whatever reason you can either execute a command  or fetch a URL  to gracefully shutdown your container.

You can define a `preHook` in the `lifecycle` section of your container spec. For example, for nginx, you have the following section in your container spec.

```
lifecycle:
  preStop:
    exec:
      command: [
        # Gracefully shutdown nginx
        “/usr/sbin/nginx”, “-s”, “quit”
      ]
```

Alternatively, you can issue a HTTP get against an endpoint:
```
httpGet:
          path: /shutdown
          port: 8080
```

#### Handling SIGTERM

Docker will send the `SIGTERM`  command to `PID` 1 of a container.  This should result in graceful shutdown of all processes in a container. 

If you have your own custom service, you need to ensure it has a handler for `SIGTERM` and will gracefully shut itself and all children processes.

If you’re using a 3rd party service, read the documentation. Ensure that the service can gracefully shut itself down on `SIGTERM`.

If you’re using a wrapper to start your service process, you need to ensure the wrapper can propagate `SIGTERM` to all processes.

The duration of this period is `TerminationGracePeriodSeconds` attribute in Container. 

## Carry over your services
Carrying over your services can be as simple as as deploying them again **as long as you  ensure they pick up the existing storage resources**. In order to achieve this, you’ll need to create your `PersistentVolume` objects manually and:

* Bind them to existing storage resource (e.g. Azure Managed Disk, Azure File etc) that they have their data
* Your service uses this specific  `PersistentVolume` and do not issue a new claim.

Once the following two steps are done for all services, you can proceed with deploying them. 

### Binding to an existing storage resource

Binding to an existing storage requires you to create `PersistentVolume` and specify details of your storage resource. This part is likely to be specific to your cloud provider. 

As an example here’s how you can use an existing Azure Managed disk on your `PersistentVolume`.  

```
apiVersion: v1
kind: PersistentVolume
metadata:
	# give your persistent volume a meaningful name
  name: myservice-pv
  labels:
  # label your PV so you can easily select it from your PVC	
    usage: myservice-pv
spec:
  capacity:
    storage: 5Gi 
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  azureDisk: 
	  # set this if it’s a managed disk
    kind: Managed
    # name of the disk, can be retrieved from portal
    diskName: <name of the disk>
    # uri of the disk, can be retrieved from portal
    diskURI: <uri of the disk>
```

### Picking up an existing persistent volume from your service
This part will be service specific and how your service gets its `PersistentVolume`. 

If your service deployment already includes  a `PersistentVolumeClaim` you can modify it to pick up a specific `PersistetnVolume`. For the example case in the previous section, following `PersistentVolumeClaim` would do:

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
	# give your persistent volume claim a meaningful name
  name: myservice-pvc
  # Set this annotation to NOT let Kubernetes automatically create
  # a persistent volume for this volume claim.
  annotations:
    volume.beta.kubernetes.io/storage-class: ""
spec:
	# ensure that spec matches what you have in your PV (e.g. access mode, size etc)
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  selector:
    # To make sure we match the claim with the exact volume, match the label
    matchLabels:
      usage: myservice-pv
```

If you are not creating your `PersistentVolumeClaims` explicitly, but rather via some claim template, you need to update your template to match a specific `PersistentVolume`. Continuing from the example above, below `StatefulSet` will automatically create a `PersistentVolumeClaim` that automatically picks up the `PersistentVolume` from the previous section.

```
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: "nginx"
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: k8s.gcr.io/nginx-slim:0.8
        ports:
        - containerPort: 80
          name: web
        volumeMounts:
        - name: www
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: myservice-pvc
      # Set this annotation to NOT let Kubernetes automatically create
      # a persistent volume for this volume claim.
      annotations:
        volume.beta.kubernetes.io/storage-class: ""
    spec:
		# ensure that spec matches what you have in your PV (e.g. access mode, size etc)
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi
      selector:
        # To make sure we match the claim with the exact volume, match the label
        matchLabels:
          usage: myservice-pv
```

Once you ensure that all your services point existing `PersistentVolume` object, you can deploy them.

