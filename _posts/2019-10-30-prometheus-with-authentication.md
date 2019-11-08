---
layout: post
title: Authentication for Prometheus via nginx sidecar
author: yufufi
---

Out of the box `Prometheus` does not support any authentication mechanism. If you like to expose your instance externally, and you don't have the luxury of hiding it behind a VPN of some kind, one of your options is to put it behind an `nginx` proxy.

## Preparing `nginx`

See below for a basic `nginx` configuration:

1. Listens to port 8080
2. Sends all requests to `/` to `http://localhost:9090`
3. Rely on the `htpasswd` file for accepted credentials.

Execute `htpasswd -c <filename> <username>` to create a file  with the given user.

```
error_log /dev/stdout info;
events {
  worker_connections  4096;
}

http {
  include    mime.types;
  access_log /dev/stdout;

    server {
            listen 8080 ;
            listen [::]:8080 ;

            server_name _;

            auth_basic "Protected by sidecar proxy!";
            auth_basic_user_file htpasswd;
            location / {
                proxy_pass http://localhost:9090;
            }
    }
}
```

There are couple of options out there to use as a base `nginx`. See the [official Alpine based one](https://hub.docker.com/_/nginx) or another one from [bitnami](https://github.com/bitnami/bitnami-docker-nginx).

A very quick and dirty `Dockerfile` for the purpose:

1. Starts with Bitnami base image
2. Copies the password file and the configuration file.
3. Gives permission to everyone to the nginx folder.

```
FROM bitnami/nginx:latest
COPY htpasswd /opt/bitnami/nginx/conf/
COPY nginx.conf /opt/bitnami/nginx/conf/
USER 0
RUN chmod -R a+rwx /opt/bitnami/nginx
```

## Preparing `prometheus`

Assuming that you're using [`prometheus-operator`](https://github.com/coreos/prometheus-operator), you need to extend your `prometheus` deployment as such:

```
  externalUrl: http://localhost:8080/   
  containers:
    - name: nginx-sidecar-proxy
      image: <your nginx image>
      ports:
      - containerPort: 8080
```

## Putting it together
The rest is to setup a `service` that exposes `nginx:8080` to outside world.

