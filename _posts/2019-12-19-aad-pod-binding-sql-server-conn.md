---
layout: post
title: Securing Access to SQL Server with Managed Identities and aad-pod-binding
author: haluk.aktas@deepnetwork.com
---

A common challenge when building cloud applications is how to manage the credentials in your code for authenticating to cloud services. In this blog post, I will try to explain how we managed to transform our application to use `managed identities` while connecting SQL database instance in pod level by using [aad-pod-binding](https://github.com/Azure/aad-pod-identity).

## Managed Identities and Their Relations with Service Principals

Azure managed identities provide Azure services with an automatically managed identity in Azure AD. You can use the identity to authenticate to any service that supports Azure AD authentication, including Key Vault, without any credentials in your code. With the help of this feature, there is no need to think about secret rotation for keys and connection strings. Each corresponding access token is generated at runtime by the [Azure Instance Metadata Service](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service).

There are two types of managed identities in Azure: `System Assigned` and `User Assigned`. The difference between these two is system assigned identity can be enabled for a resource that supports managed identity while provisioning. After the identity is created, it is bound to the lifecycle of a resource which means whenever the related resource is deleted, the corresponding identity is deleted as well. But the user assigned identity is a standalone Azure resource and its lifecycle is not tied to any resource that it is bind to. Also, one user identity can be assigned to multiple Azure service instances. For further reading, you can follow the [official documentation.](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview#how-does-the-managed-identities-for-azure-resources-work)

In this blog post, we are going to define and use a `User Assigned Managed Identity`, and this identity will be used to connect to the SQL Server Database Instance.

### Managed Identity vs Service Principal - An Introduction

Before going any further, the relation between managed identity and service principal needs to be well understood. In AAD, applications are represented with `Service Principals` and they define the access policy and permissions for the corresponding application in a single Azure AD tenant. You can follow [this article](https://medium.com/@ihorkliushnikov/azure-active-directory-application-or-service-principal-b5a5e14f2a23) to get a better understanding about the concept. Service Principal is limited when it comes to application password handling, secret rotation and contextual security and `Managed Identities` feature adds one layer on top of service principal to improve its functionality.

When you create a `managed identity`, Azure Resource Manager creates corresponding service principal with the same name as the corresponding identity in Azure AD. You cannot assign new managed identity to an existing service principal. It has to be co-created. Also, this service principal object is not visible through Azure Portal. When you assign this identity to any service instance VM, the Azure Instance Metadata Service identity endpoint is updated with our identity service principal client ID and certificate. In short, when accessing resources with assigned identity, the underlying service principal credentials are used by the Azure Active Directory to grant access to resources. You can assign the required roles for your service principal to access the desired resource.

For example if you create a user assigned identity with the following Azure cli command, you get the output like:

```
az identity create -g myResourceGroup -n myIdentityName -o json

{
"clientId": "xxxxxxx-cf3e-xxxxx-8432-xxxxxxxxxx",
  "clientSecretUrl": "https://control-westeurope.identity.azure.net/subscriptions/xxxxxxx-xxxxxxx-4031-9e8b-xxxxxxxxx/resourcegroups/myResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myIdentityName/credentials?tid=xxxxxxxx-8072-xxxxxxx-bf43-xxxxxxxx&oid=xxxxxxx-e50b-xxxxxxx-b58f-xxxxxxxxxx&aid=386fc565-xxxxxxxxx-44c0-xxxxxxx-xxxxxxxxxx",
  "id": "/subscriptions/xxxxxxx-cebc-xxxxxx-9e8b-xxxxxxxxx/resourcegroups/myResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/testidentity",
  "location": "westeurope",
  "name": "myIdentityName",
  "principalId": "xxxxxxxxx-e50b-xxxxxxx-b58f-xxxxxxxxx",
  "resourceGroup": "myResourceGroup",
  "tags": {},
  "tenantId": "xxxxxxxxx-8072-xxxxx-bf43-xxxxxxxxx",
  "type": "Microsoft.ManagedIdentity/userAssignedIdentities"
}
```

In order to see the underlying service principal created for this identity you can run the following command. Notice the service principal name is the same as the identity name. And if you search this service principal in Azure Portal, you are unable to see it.

```
az ad sp list --display-name "myIdentityName"
```

When you closely inspect the output of this command, you can see the `clientId` and `principalId` for identity corresponds to `appId` and `objectId` of the underlying service principal. And the service principal type is `ManagedIdentity`. If it were a regular application, its type would be `Application`

## Secure SQL Database Connection by Using User Defined Managed Identity

In [official documentation](https://docs.microsoft.com/en-us/azure/app-service/app-service-web-tutorial-connect-msi#modify-aspnet-core), you can see how managed identity is mapped to SQL Database and alternatively, you can add your `user assigned managed identity` to Azure AD group and then create contained database user with the same name as this group name. With this approach, you can grant database access to your identity. But it is not stated how this mapping works and there is no direct link to the related topic. But you can follow [this link](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-aad-authentication-configure?tabs=azure-powershell#create-contained-database-users-in-your-database-mapped-to-azure-ad-identities) to get the idea.

Basically, since database users cannot be created from the Azure portal, we need to define them directly in the database with using T-SQL statements. To create an Azure AD based contained database user, we need to first grant database access to Azure AD user or group by assigning them as the Active Directory admin of the SQL Database server from portal or while provisioning the SQL server (available on portal under SQL Server -> Active Directory admin > Set admin).

Later, you can login to SQL Database instance from `SSMS` by supplying credentials for your AD user or group account which is assigned as AD admin of the SQL Server previously. If you intend to perform this operation through `CI/CD` pipeline like `Azure DevOps`, then you can follow [this article](https://blog.bredvid.no/handling-azure-managed-identity-access-to-azure-sql-in-an-azure-devops-pipeline-1e74e1beb10b).  After that you can use the following T-SQL statement:

```
CREATE USER <Azure_AD_principal_name> FROM EXTERNAL PROVIDER;

ALTER ROLE db_datareader ADD MEMBER [<Azure_AD_principal_name];
```

Here, `Azure_AD_principal_name` can be a managed identity, Azure AD user or group. In summary, with defining Azure AD group and creating a corresponding contained database user, you can give database access to multiple identities without creating separate contained database user for each one. Once you define an Azure AD based contained database user, you can grant the user additional permissions like you do for your regular database users.


## Create Pod Level Identity Bindings 

After getting better understanding about what managed identities are and how we can create Azure AD based contained database user in our SQL Database, we should somehow assign our identity to our application. But how? 

If you read the [official document](https://docs.microsoft.com/en-us/azure/app-service/app-service-web-tutorial-connect-msi#modify-aspnet-core), you can see Azure App Service is used. And the assignment is performed with this simple az cli command:

```
az webapp identity assign --resource-group myResourceGroup --name <myAppName>
```

After running this command, Azure Resource Manager configures the identity on the underlying VM and updates the Azure Instance Metadata Service Identity endpoint with the assigned managed identity service principal client ID and certificate. And the code that is running on the VM can request a token from Azure Instance Metadata Service identity endpoint, accessible only from within the VM: http://169.254.169.254/metadata/identity/oauth2/token.

However for our scenario, we are not using Azure App Service. We just deploy our `.NET Core` application to the `k8s` cluster. So we don't have such an option to directly assign our application to user assigned managed identity. When we deploy our application to the cluster, somehow we should be able to assign these identities in the pod level. Fortunately, [AAD Pod Identity](https://github.com/Azure/aad-pod-identity) is used for this purpose. It enables `k8s` applications to access cloud resources securely with Azure AD. 

[This article](https://medium.com/microsoftazure/pod-identity-5bc0ffb7ebe7) is very nice to get an idea of AAD Pod Identity concept. Basically, when a pod is scheduled to a node, `aad-pod-identity` ensures that a pre-configured user assigned identity is assigned to the underlying VM. If you follow the [Getting Started](https://github.com/Azure/aad-pod-identity#getting-started) steps, you can easily setup your application in cluster with identity binding.
Of course, before starting you have to have a running `k8s` cluster. 

First we need to enable AAD Pod Identity in our cluster by deploying it. It includes 1 `NMI` (Node Managed Identity) daemon set and 2 `MIC` (Managed ıdentity Controller) pods and several custom resources. In order to get better insights about this plugin, you can read [concept](https://github.com/Azure/aad-pod-identity/blob/master/docs/design/concept.md) and investigate the [concept diagram](https://github.com/Azure/aad-pod-identity/blob/master/docs/design/concept.png).

Since our cluster is non-RBAC, deploy with the following command:

```
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment.yaml
```

Create User Assigned Managed Identity and note the `clientId` from output for later use:

```
az identity create -g myResourceGroup -n myidentity -o json
```

Install created identity to our cluster by deploying the following:

```
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: myidentity
spec:
  type: 0
  ResourceID: /subscriptions/<subid>/resourcegroups/myResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myidentity
  ClientID: myClientId
```

`myClientId` is the clientId of previously defined managed identity.

Install the Azure Identity Binding with the following deployment:

```
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: my-azure-identity-binding
spec:
  AzureIdentity: myidentity
  Selector: connectsqlserver
```

In order to match an identity binding, the pod has to define a label with the key `aadpodidbinding` and the value `connectsqlserver`. The label value can be anything. Here in order to describe its intended usage, label value is set to `connectsqlserver`.

After deploying identity binding to our cluster, the only thing remained is to provide custom label value `connectsqlserver` to our pods `aadpodidbinding` label. When Managed Identity Controller (`MIC`) detects matching between our pod label with corresponding binding, the `MIC` adds assigned identity `AzureAssignedIdentities` to the cluster node. Before deploying our application to the cluster, we must label our pod as:

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aad-binding-test-application
spec:
  template:
    metadata:
      labels:
        app: another-label-value
        aadpodidbinding: connectsqlserver
...
```

After setting managed identity with its permissions in pod level, we can update our `.NET Core` application code. First, the following `Nuget` package have to be installed:

```
Install-Package Microsoft.Azure.Services.AppAuthentication
```

In order to connect to Azure SQL Server database, provide the connection string with only database server and database instance name without username, password credentials since the access token is going to be retrieved at runtime with aad-pod-identity-binding.

```
    String connString = "Server=tcp:mySQLServer.database.windows.net,1433;  Database=mySQLServerDatabaseInstance";

            var conn = new SqlConnection(connString)
            {
                AccessToken = await new AzureServiceTokenProvider().GetAccessTokenAsync("https://database.windows.net/")
            };

            return conn;
```

After deploying of our application to the cluster, you can inspect the `MIC` pod logs to see how identity bindings are performed dynamically.

```
kubectl get logs

NAME                  READY   STATUS    RESTARTS   AGE
mic-bf98c7d8d-9kqdt   1/1     Running   0          72s
mic-bf98c7d8d-bs47j   1/1     Running   0          72s
nmi-tb6d5             1/1     Running   0          72s

kubectl logs mic-bf98c7d8d-9kqdt -f

I1223 08:24:49.360593       1 main.go:79] Starting mic process. Version: 1.5.4. Build date: 2019-12-17-20:49
I1223 08:24:49.360640       1 main.go:98] kubeconfig (/etc/kubernetes/kubeconfig/kubeconfig) cloudconfig (/etc/kubernetes/azure.json)
I1223 08:24:49.365850       1 main.go:109] Client QPS set to: 5. Burst to: 5
I1223 08:24:49.365924       1 mic.go:92] Starting to create the pod identity client. Version: 1.5.4. Build date: 2019-12-17-20:49
I1223 08:24:49.550699       1 mic.go:98] Kubernetes server version: v1.14.8
I1223 08:24:49.551129       1 log.go:16] Initialized health probe on port &[8080]
I1223 08:24:49.551149       1 log.go:11] Started health probe
I1223 08:24:49.551200       1 log.go:16] Registered views for metric%!(EXTRA *[]interface {}=&[])
I1223 08:24:49.551226       1 log.go:11] Starting Prometheus exporter
I1223 08:24:49.551232       1 log.go:16] Registered and exported metrics on port &[8888]
I1223 08:24:49.551238       1 mic.go:164] Initiating MIC Leader election
I1223 08:24:49.551245       1 leaderelection.go:175] attempting to acquire leader lease  default/aad-pod-identity-mic...
I1223 08:24:49.581595       1 leaderelection.go:184] successfully acquired lease default/aad-pod-identity-mic
I1223 08:24:49.683401       1 pod.go:73] Pod cache synchronized. Took 100.105529ms
I1223 08:24:49.683431       1 pod.go:80] Pod watcher started !!
I1223 08:24:49.783495       1 log.go:11] CRD informers started
I1223 08:24:49.783548       1 mic.go:257] Sync thread started.
I1223 12:21:37.710255       1 mic.go:787] Processing node aks-nodepool1-xxxx-vmss, add [1], del [0]
I1223 12:21:37.710287       1 crd.go:341] Got assigned id aad-binding-test-application-5848d7484d-hd9jv-default-testidentity to assign
I1223 12:21:38.308584       1 cloudprovider.go:199] Updating user assigned MSIs on aks-nodepool1-xxxxx-vmss
I1223 12:22:16.513777       1 crd.go:539] Updating assigned identity default/aad-binding-test-application-5848d7484d-hd9jv-default-testidentity status to Assigned
I1223 12:22:16.531218       1 mic.go:367] Work done: true. Found 1 pods, 1 ids, 1 bindings
I1223 12:22:16.531261       1 mic.go:368] Total work cycles: 19, out of which work was done in: 1.
I1223 12:22:16.531293       1 stats.go:98] ** Stats collected **
I1223 12:22:16.531297       1 stats.go:81] Pod listing: 31.5µs
I1223 12:22:16.531316       1 stats.go:81] ID listing: 2.001µs
I1223 12:22:16.531321       1 stats.go:81] Binding listing: 5.3µs
I1223 12:22:16.531324       1 stats.go:81] Assigned ID listing: 600ns
I1223 12:22:16.531327       1 stats.go:81] System: 43.601µs
I1223 12:22:16.531330       1 stats.go:81] CacheSync: 0s
I1223 12:22:16.531333       1 stats.go:81] Cloud provider get: 575.232926ms
I1223 12:22:16.531337       1 stats.go:81] Cloud provider put: 38.205141564s
I1223 12:22:16.531340       1 stats.go:81] Assigned ID addition: 23.001988ms
I1223 12:22:16.531343       1 stats.go:81] Assigned ID deletion: 0s
I1223 12:22:16.531364       1 stats.go:88] Number of cloud provider PUT: 1
I1223 12:22:16.531367       1 stats.go:88] Number of cloud provider GET: 1
I1223 12:22:16.531370       1 stats.go:88] Number of assigned ids created in this sync cycle: 1
I1223 12:22:16.531373       1 stats.go:88] Number of assigned ids deleted in this sync cycle: 0
I1223 12:22:16.531376       1 stats.go:81] Find assigned ids to create: 0s
I1223 12:22:16.531379       1 stats.go:81] Find assigned ids to delete: 0s
I1223 12:22:16.531382       1 stats.go:81] Total time to assign or remove IDs: 38.820957s
I1223 12:22:16.531386       1 stats.go:81] Event recording: 0s
I1223 12:22:16.531389       1 stats.go:81] Total: 38.821196703s
I1223 12:22:16.531392       1 stats.go:127] *********************
```

## Considerations While Using aad-pod-identity in Cluster

There are some [scenarious](https://itnext.io/using-aad-pod-identity-in-your-azure-kubernetes-clusters-what-to-watch-out-for-73d5d73960f) that you should be aware of before using cluster level pod identity binding. There are some in-work improvements to handle these issues according to the [article](https://medium.com/microsoftazure/pod-identity-5bc0ffb7ebe7). You can see the details of them from the provided article. For example, Azure Kubernetes Service (`AKS`) stores Service Principal credential used to talk with the Azure API in plain-text. In addition, the deployed `MIC` pod mounts that file into itself. So, any user with execute access on `MIC` can access to these credentials.

## Summary

In this blog, we have seen how `Managed Service Identities` can be used to connect to `Azure SQL Database` without manually handling credentials, in cluster level with the help of `aad-pod-identity-binding`.