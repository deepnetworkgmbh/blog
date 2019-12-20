---
layout: post
title: Accessing SQL Server with Managed Identities and aad-pod-binding k8s plugin
author: haluk.aktas@deepnetwork.com
---

Common security işi ekle
In this blog post, I will try to explain how we managed to transform our application to use managed identities while connecting database instance in pod level by using aad-pod-binding plugin for k8s which is a side project of Microsoft Azure Team. In the future it is intented to be a part of AKS as a default.

Introda detay degil de genel bilgi ver.
## Managed Identities and Their Relations with Service Principals

azure keyvault olaylarını çıkar. 
Username password challengeini çıkar. challengei detaylı anlatma zaten biliniyo.

In one of our applications, we are connecting to Azure SQL Database Instance with connection string which includes username and password credentials. While developing the application locally, these credentials are fetched by using Azure CLI or powershell scripts and then supplied to our application with config parameters. But in the production, these secrets are fetched from KeyVault and then corresponding secret is generated in the k8s cluster in our release pipeline. And finally, these secrets are loaded to our containers in runtime by supplying volume mounts in our pod definitons. This is a huge effort. And it is really hard to keep track of all the secrets and their rotations regularly.

In order to resolve these issues Azure Managed Identities are emerged. The feature provides Azure services with an automatically managed identity in Azure AD. You can use the identity to authenticate to any service that supports Azure AD authentication, including Key Vault, without any credentials in your code.

There are two types of managed identities in Azure: `System Assigned` and `User Assigned`. The difference between these two is system assigned identity can be enabled for a resource that supports managed identity while provisioning. After the identity is created, it is bound to the lifecycle of a resource which means whenever the related resource is deleted, the corresponding identity is deleted as well. But the user assigned identity is a standalone Azure resource and it is lifecycle is not tied to any resource that it is bind to. Also, one user identity can be assigned to multiple Azure service instances. For further reading, you can follow the [official documentation.](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview#how-does-the-managed-identities-for-azure-resources-work)

In this blog post, we are going to define and use a `User Assigned Identity`, and this identity will be used to connect to the SQL Database Instance.

### Managed Identity vs Service Principal - An Introduction
you cannot assign new managed identity to an existing service principal. It has to be co-created.
Before going any further, let me explain the relation between managed identity and service principal because it is a little bit hard to grasp at first. When you create a `managed identity`, Azure Resource Manager creates corresponding service principal in Azure AD. When you assign this identity to any service instance VM, the Azure Instance Metadata Service identity endpoint is updated with our identity service principal client ID and certificate. In short, when accessing resources with assigned identity, the underlying service principal credentials are used by the Azure Active Directory to grant access to target resources. You can assing the required roles for your service principal to access the desired resource.

For example if you create a user assigned identity with the following Azure cli command, you get the output like:

`make 00000 -> 11111-xxxxxx-2222-xxxxx `

```
az identity create -g myResourceGroup -n myIdentityName -o json



{
  "clientId": "00000000-0000-0000-0000-000000000000",
  "clientSecretUrl": "https://control-eastus.identity.azure.net/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/myresourcegroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myidentity/credentials?tid=00000000-0000-0000-0000-000000000000&oid=00000000-0000-0000-0000-000000000000&aid=00000000-0000-0000-0000-000000000000",
  "id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/myresourcegroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myidentity",
  "location": "eastus",
  "name": "myidentity",
  "principalId": "00000000-0000-0000-0000-000000000000",
  "resourceGroup": "myresourcegroup",
  "tags": {},
  "tenantId": "00000000-0000-0000-0000-000000000000",
  "type": "Microsoft.ManagedIdentity/userAssignedIdentities"
}
```

In order to see the underlying service principal created for this identity you can run the following command. Notice the service principal name is the same as the identity name. And if you search this service principal in Azure Portal, you are unable to see it.

```
az ad sp list --display-name "myIdentityName"
```

When you closely inspect the output of this command, you can see the `clientId` and `principalId` for identity corresponds to `appId` and `objectId` of the underlying service principal. And the service principal type is `ManagedIdentity`. If it were a regular application, the its type would be `Application`

## Secure SQL Database Connection by Using User Defined Managed Identity
Kısalt burayı çok uzun.
As explained in the beginning of this blog post, before applying managed identities, our application is connected to database with a connection string that contains username and password credentials. But we can avoid this potential vulnerability by using managed indetities. In [official documentation](https://docs.microsoft.com/en-us/azure/app-service/app-service-web-tutorial-connect-msi#modify-aspnet-core), you can see how managed identity is mapped to SQL Database and alternatively, you can add your user assigned managed identity to Azure AD group and then create contained database user with the same name as this group name. With this approach, you can grant database access to your identity. But it is not stated how this mapping works and there is no direct link to the related topic. But you can follow [this link](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-aad-authentication-configure?tabs=azure-powershell#create-contained-database-users-in-your-database-mapped-to-azure-ad-identities) to get the idea.

Basically, since database users cannot be created from the Azure portal, we need to define them directly in the database with using T-SQL statements. To create an Azure AD based contained database user, we need to first grant database access to Azure AD user or group by assigning them as the Active Directory admin of the SQL Database server from portal or while provisioning the SQL server. 
And then you can login to SQL Database instance from SSMS by supplying credentials for your AD user or group account which is assigned as AD admin of the SQL Server previously. After that you can use the following T-SQL statement:

Eger CI/CD pipeline'ında bu operasyonu AD user olmadan yapmaya çalısırsak su linke reference ver: https://blog.bredvid.no/handling-azure-managed-identity-access-to-azure-sql-in-an-azure-devops-pipeline-1e74e1beb10b 

```
CREATE USER <Azure_AD_principal_name> FROM EXTERNAL PROVIDER;

ALTER ROLE db_datareader ADD MEMBER [<Azure_AD_principal_name];
```

`Azure_AD_principal_name` can be a managed identity, Azure AD user or group. So with defining Azure AD group and creating a corresponding contained database user, you can give database access to multiple identities without creating separate contained database user for each one. Once you define an Azure AD based contained database user, you can grant the user additional permissions.


## Create Pod Level Identity Bindings 

After getting better understanding about what managed identities are and how we can create Azure AD based contained database user in our SQL Database, we should somehow assign our identity to our application. But how? 

If you read the [official document](https://docs.microsoft.com/en-us/azure/app-service/app-service-web-tutorial-connect-msi#modify-aspnet-core), you can see Azure App Service is used. And the assignment is performed with this simple az cli command:

```
az webapp identity assign --resource-group myResourceGroup --name <app-name>
```

After running this command, Azure Resource Manager configures the identity on the underlying VM and updates the Azure Instance Metadata Service identity endpoint with the assigned managed identity service principal client ID and certificate. And the code that is running on the VM can request a token from 
 Azure Instance Metadata Service identity endpoint, accessible only from within the VM: http://169.254.169.254/metadata/identity/oauth2/token.

However for our scenario, we are not using Azure App Service. We just deploy our .net core application to the k8s cluster. So we don't have such an option to directly assign our application to user assigned managed identity. When we deploy our application to the cluster, somehow we should be able to assing these identities in the pod level. Fortunately, [AAD Pod Identity](https://github.com/Azure/aad-pod-identity) is used for this purpose. It enables k8s applications to access cloud resources securely with Azure AD. 

[This article](https://medium.com/microsoftazure/pod-identity-5bc0ffb7ebe7) is very nice to get the idea of AAD Pod Identity concept. Basically, when a pod is scheduled to a node, `aad-pod-identity` ensures that a pre-configured user assigned identity is assigned to the underlying VM. If you follow the [Getting Started](https://github.com/Azure/aad-pod-identity#getting-started) steps, you can easily setup your application in cluster with identity binding.
Of course, before starting you have to have a runnnig k8s cluster. 

First we need to enable AAD Pod Indetity in our cluster by deploying it. It includes 1 `NMI` (Node Managed Identity) daemon set and 2 `MIC` (Managed ıdentity Controller) pods and several custom resources. In order to get better insights about this plugin, you can read [concept](https://github.com/Azure/aad-pod-identity/blob/master/docs/design/concept.md) and investigate the [concept diagram](https://github.com/Azure/aad-pod-identity/blob/master/docs/design/concept.png).

Since our cluster is non-RBAC, deploy with the following command:

```
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment.yaml
```

Create User Assgined Managed Identity and note the `clientId` from output for later use:

```
az identity create -g myResourceGroup -n myIdentity -o json
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
  ClientID: clientId
```

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

In order to match an identity binding, the pod has to define a label with the key `aadpodidbinding` and the value `connectsqlserver`. 

In order to connect to Azure SQL Server database, provide the connection string with only database server and database instance name without username, password credentials since the identity is assigned to our pods.

```
    String connString = "Server=tcp:mySQLServer.database.windows.net,1433;  Database=mySQLServerDatabaseInstance";

            var conn = new SqlConnection(connString)
            {
                AccessToken = await new AzureServiceTokenProvider().GetAccessTokenAsync("https://database.windows.net/")
            };

            return conn;
```

