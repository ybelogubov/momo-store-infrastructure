# momo-store-infra
Repository contains files reqiered for deployment of a managed Kubernetes cluster on Yandex Cloud platform 

## Getting started
Cluster's structure described and supposed to be deployed by using Terraform.
The deployment process consist of several steps (each described in details below):
1. Registration on the Yandex.Cloud platform and preparing the account for deploment of the managed K8S cluster;
2. Creating a Cloud Object Storage on the platform (for terraform state);
3. Installing Terraform, YandexCloud CLI and copying repository data on your workstation;
4. Obtainig required data - keys, resourse' IDs etc.;
5. Modifying files and deploying the cluster;
6. Cluster's removing;

## Prepare your cloud instance on the Yandex.Cloud 
- Go to the [management console](https://console.cloud.yandex.com/) and log in to Yandex Cloud or create an account if you do not have one yet.
- On the [billing page](https://console.cloud.yandex.com/billing), make sure you linked a [billing account](https://cloud.yandex.com/docs/billing/concepts/billing-account) and it has the "ACTIVE" or "TRIAL_ACTIVE" status. If you do not yet have a billing account, [create one](https://cloud.yandex.com/docs/billing/quickstart/#create_billing_account).
- If you do not have a [folder](https://cloud.yandex.com/docs/resource-manager/concepts/resources-hierarchy#folder) yet, [create one](https://cloud.yandex.com/docs/resource-manager/operations/folder/create).
- Make sure you have enough [resources available in the cloud](https://cloud.yandex.com/docs/managed-kubernetes/concepts/limits).
- Create [service account](https://cloud.yandex.com/en/docs/iam/operations/sa/create) with the [editor](https://cloud.yandex.com/en/docs/iam/concepts/access-control/roles#editor) role
- Create a [static key under the service account](https://cloud.yandex.com/en/docs/iam/operations/sa/create-access-key) 

Copy following data (you need it for the deploy process via terraform):
    - folder ID in Yandex.Cloud
    - ID of your Yandex Cloud
    - Static key ID for the service account
    - Access token (Private key) for the static key (under service account)

```
cd existing_repo
git remote add origin https://gitlab.praktikum-services.ru/yu.belogubov/momo-store-infra.git
git branch -M main
git push -uf origin main
```

## Create a Yandex Cloud Object Storage
Please follow the [offical user guide](https://cloud.yandex.com/en/docs/storage/quickstart) in order to create a new storage. Make sure that the service account created on the previous step have access to it (ACL roles).
Copy the bucket name - you'll need it for the terraform deploy step. 

## Installing Terraform, YandexCloud CLI and copying repository data on your workstation
- Install [Terraform](https://cloud.yandex.com/en/docs/tutorials/infrastructure-management/terraform-quickstart#install-terraform)
- Install [YandexCloud CLI](https://cloud.yandex.com/en/docs/cli/quickstart#install) and create profile
- Install [Kubectl](https://kubernetes.io/ru/docs/tasks/tools/install-kubectl/)
- Install [Helm](https://helm.sh/docs/intro/install/)
- Install [JQ tool](https://stedolan.github.io/jq/)
- Copy data from this repo to your local workstation

## Prepare DOMAIN name
In case you do not have a domain name - register a new one (at any hosting). In settings for NS servers:

```
ns1.yandexcloud.net
ns2.yandexcloud.net
``` 

Register 2 subdomains:
```
monitoring.<your_domain>
grafana.<your_domain>
```

## Managed K8S cluster deploy
- create a temporary access token for YC:
```
yc iam create-token
```
- put the token into the "terraform.tfvars" file - value for iam_token variable
- provide values for the "var.tf" file - previously copied IDs of cloud, folder and domain name
- provide ID of the static key for service account in the "main.tf" file in the "backend "s3" section:
```
  backend "s3" {
    endpoint   = "storage.yandexcloud.net"
    bucket     = "<YOUR_BUCKET_NAME>"
    region     = "ru-central1"
    key        = "terraform/k8s-terraform.tfstate" #<< path to the state file on the storage
    access_key = "<ID_OF_STATIC_KEY>"
    secret_key = "<PRIVATE_KEY_VALUE>"
```
- run following commands to deploy the cluster via terraform:
```
cd existing_repo
terraform init
terraform plan
terraform apply
``` 
Deploy of the resources require some time - 10-30 minutes.
Results of the operation can be checked in the web UI console.

- get the cluster id from the web UI
- [set up the kubectl (to work with your new cluster)](https://cloud.yandex.com/en/docs/managed-kubernetes/operations/connect/#kubectl-connect):
```
yc managed-kubernetes cluster \
  get-credentials k8s-cluster \
  --external
```
- check cluster info:git 
```
kubectl cluster-info
```
At this step you must see ip address of the control plane 
"Kubernetes control plane is running at https://xxx.xxx.xxx.xxx"

## Create and validate a certificate
- [Issue the certificate for your domain name](https://cloud.yandex.com/en/docs/certificate-manager/operations/managed/cert-create)
- [Validate the certificate](https://cloud.yandex.com/en/docs/certificate-manager/operations/managed/cert-validate)
- Obtain certificate ID
```
yc certificate-manager certificate list
```

## Install Application Load Balancer Ingress Controller
- create a static key for the cluster service account:
```
yc iam key create \
    --service-account-name k8s-sa \
    --format=json \
    --output ./sa-key.json
```
- run following command in order to deploy the ALB Ingress Controller from a helm chart. Put folder and cluster IDs in the command:
```
export HELM_EXPERIMENTAL_OCI=1 && \
cat sa-key.json | helm registry login cr.yandex --username 'json_key' --password-stdin && \
helm pull oci://cr.yandex/yc-marketplace/yandex-cloud/yc-alb-ingress/yc-alb-ingress-controller-chart \
  --version v0.1.16 \
  --untar && \
helm install \
  --namespace default \
  --set folderId=<YOUR_CLOUD_FOLDER_ID> \
  --set clusterId=<YOUR_CLUSTER_ID> \
  --set-file saKeySecretKey=sa-key.json \
  yc-alb-ingress-controller ./yc-alb-ingress-controller-chart/
```
expected result:
  - deployment "yc-alb-ingress-controller"
  - 2 pods "yc-alb-ingress-controller-xxxx"

## How to remove the cluster (resources)

Perform following command:
```
terraform destroy
```

