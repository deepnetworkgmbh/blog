---
layout: post
title: Accessing SQL Server with Managed Identities and aad-pod-binding k8s plugin
author: haktas
---

In one of our application, we are connecting to Azure SQL Database Instance with connection string which includes username and password credentials. These credentials are stored in Key Vault to be able to secure them without pushing those to the repository. While developing the application locally,these credentials are fetched by using Azure CLI or powershell scripts and then supplied to our application with config parameters. But in the production, these secrets are fetched from KeyVault and then corresponding secret is generated in the k8s cluster in our release pipeline. And finally, these secrets are loaded to our containers in runtime by supplying volume mounts in our pod definitons. This is a huge effort. And it is really hard to keep track of all the secrets and their rotations regularly.

In order to resolve these issues Azure Managed Identities are emerged. The feature provides Azure services with an automatically managed identity in Azure AD. You can use the identity to authenticate to any service that supports Azure AD authentication, including Key Vault, without any credentials in your code.

In this blog post, I will try to explain how we are managed to transform our application to use managed identities while connecting database instance in pod level by using aad-pod-binding plugin for k8s which is a side project of Microsoft Azure Team. In the future it is intented to be a part of AKS as a default.

## Managed Identities and Their Relations with Service Principals


## Secure SQL Database Connection by Using User Defined Managed Identity


## Create Pod Level Identity Bindings 