terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.89"
    }
    helm = {
      source = "hashicorp/helm"
      version = "2.9.0"
    }
  }
  backend "s3" {
    endpoint   = "storage.yandexcloud.net"
    bucket     = "<NAME_OF_YOUR_BUCKET>"
    region     = "ru-central1"
    key        = "terraform/k8s-terraform.tfstate" #path to the terraform state file on s3 storage
    access_key = "<ID_OF_STATIC_KEY>"
    secret_key = "<YOUR_PERSONAL_KEY>"

    skip_region_validation      = true
    skip_credentials_validation = true
  }
}

locals {
  folder_id             = var.folder_id            # Set your cloud folder ID.
  k8s_version           = "1.21"            # Set the Kubernetes version.
  zone_a_v4_cidr_blocks = "10.1.0.0/16" # Set the CIDR block for subnet.
  sa_name               = "k8s-sa"            # Set the service account name.
}

provider "yandex" {
  token     = var.iam_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = "ru-central1-a"
}

resource "yandex_vpc_network" "k8s-network" {
  description = "Network for the Managed Service for Kubernetes cluster"
  name        = "k8s-network"
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in ru-central1-a availability zone"
  name           = "subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.k8s-network.id
  v4_cidr_blocks = [local.zone_a_v4_cidr_blocks]
}

resource "yandex_vpc_security_group" "k8s-main-sg" {
  description = "Security group for the Managed Service for Kubernetes cluster"
  name        = "k8s-main-sg"
  network_id  = yandex_vpc_network.k8s-network.id
}

resource "yandex_dns_zone" "dns_domain" {
  name   = replace(var.dns_domain, ".", "-")
  zone   = join("", [var.dns_domain, "."])
  public = true
  private_networks = [yandex_vpc_network.k8s-network.id]
}

resource "yandex_dns_recordset" "dns_domain_record" {
  zone_id = yandex_dns_zone.dns_domain.id
  name    = join("", [var.dns_domain, "."])
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "dns_domain_record_momitoring" {
  zone_id = yandex_dns_zone.dns_domain.id
  name    = join("", ["monitoring.",var.dns_domain, "."])
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "dns_domain_record_grafana" {
  zone_id = yandex_dns_zone.dns_domain.id
  name    = join("", ["grafana.",var.dns_domain, "."])
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

resource "yandex_vpc_address" "addr" {
  name = "static-ip"
  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}

resource "yandex_vpc_security_group_rule" "loadbalancer" {
  description            = "The rule allows availability checks from the load balancer's range of addresses"
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "TCP"
  predefined_target      = "loadbalancer_healthchecks" # The load balancer's address range.
  from_port              = 0
  to_port                = 65535
}

resource "yandex_vpc_security_group_rule" "node-interaction" {
  description            = "The rule allows the master-node and node-node interaction within the security group"
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "ANY"
  predefined_target      = "self_security_group"
  from_port              = 0
  to_port                = 65535
}

resource "yandex_vpc_security_group_rule" "pod-service-interaction" {
  description            = "The rule allows the pod-pod and service-service interaction"
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "ANY"
  v4_cidr_blocks         = [local.zone_a_v4_cidr_blocks]
  from_port              = 0
  to_port                = 65535
}

resource "yandex_vpc_security_group_rule" "ICMP-debug" {
  description            = "The rule allows receipt of debugging ICMP packets from internal subnets"
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "ICMP"
  v4_cidr_blocks         = [local.zone_a_v4_cidr_blocks]
}

resource "yandex_vpc_security_group_rule" "port-6443" {
  description            = "The rule allows connection to Kubernetes API on 6443 port from the Internet"
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "TCP"
  v4_cidr_blocks         = ["0.0.0.0/0"]
  port                   = 6443
}

resource "yandex_vpc_security_group_rule" "port-443" {
  description            = "The rule allows connection to Kubernetes API on 443 port from the Internet"
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "TCP"
  v4_cidr_blocks         = ["0.0.0.0/0"]
  port                   = 443
}

resource "yandex_vpc_security_group_rule" "outgoing-traffic" {
  description            = "The rule allows all outgoing traffic"
  direction              = "egress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "ANY"
  v4_cidr_blocks         = ["0.0.0.0/0"]
  from_port              = 0
  to_port                = 65535
}

resource "yandex_vpc_security_group_rule" "SSH" {
  description            = "The rule allows connection to Git repository by SSH on 22 port from the Internet"
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "TCP"
  v4_cidr_blocks         = ["0.0.0.0/0"]
  port                   = 22
}

resource "yandex_vpc_security_group_rule" "HTTP" {
  description            = "The rule allows HTTP traffic"
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "TCP"
  v4_cidr_blocks         = ["0.0.0.0/0"]
  port                   = 80
}

resource "yandex_vpc_security_group_rule" "NodePort-access" {
  description            = "The rule allows incoming traffic to port range of NodePort"
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  protocol               = "TCP"
  v4_cidr_blocks         = ["0.0.0.0/0"]
  from_port              = 30000
  to_port                = 32767
}

resource "yandex_vpc_security_group_rule" "port-10502" {
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  predefined_target      = "self_security_group"
  protocol               = "TCP"
  port                   = 10502
}

resource "yandex_vpc_security_group_rule" "port-10501" {
  direction              = "ingress"
  security_group_binding = yandex_vpc_security_group.k8s-main-sg.id
  predefined_target      = "self_security_group"
  protocol               = "TCP"
  port                   = 10501
}

resource "yandex_iam_service_account" "k8s-sa" {
  description = "Service account for the Managed Service for Kubernetes cluster and node group"
  name        = local.sa_name
}

resource "yandex_resourcemanager_folder_iam_binding" "editor" {
  folder_id = local.folder_id
  role      = "editor"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "vpc-admin" {
  folder_id = local.folder_id
  role      = "vpc.publicAdmin"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "cert-downloader" {
  folder_id = local.folder_id
  role      = "certificate-manager.certificates.downloader"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "compute-viewer" {
  folder_id = local.folder_id
  role      = "compute.viewer"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "alb-editor" {
  folder_id = local.folder_id
  role      = "alb.editor"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "images-puller" {
  folder_id = local.folder_id
  role      = "container-registry.images.puller"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "images-pusher" {
  folder_id = local.folder_id
  role      = "container-registry.images.pusher"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "storage-uploader" {
  folder_id = local.folder_id
  role      = "storage.uploader"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "storage-viewer" {
  folder_id = local.folder_id
  role      = "storage.viewer"
  members = [
    "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
  ]
}

resource "yandex_kubernetes_cluster" "k8s-cluster" {
  description = "Managed Service for Kubernetes cluster"
  name        = "k8s-cluster"
  network_id  = yandex_vpc_network.k8s-network.id

  master {
    version = local.k8s_version
    zonal {
      zone      = yandex_vpc_subnet.subnet-a.zone
      subnet_id = yandex_vpc_subnet.subnet-a.id
    }

    public_ip = true

    security_group_ids = [yandex_vpc_security_group.k8s-main-sg.id]
  }
  service_account_id      = yandex_iam_service_account.k8s-sa.id # Cluster service account ID.
  node_service_account_id = yandex_iam_service_account.k8s-sa.id # Node group service account ID.
  depends_on = [
    yandex_resourcemanager_folder_iam_binding.editor,
    yandex_resourcemanager_folder_iam_binding.images-puller
  ]
}

resource "yandex_kubernetes_node_group" "k8s-node-group" {
  description = "Node group for the Managed Service for Kubernetes cluster"
  name        = "k8s-node-group"
  cluster_id  = yandex_kubernetes_cluster.k8s-cluster.id
  version     = local.k8s_version

  scale_policy {
    fixed_scale {
      size = 1 # Number of hosts
    }
  }

  allocation_policy {
    location {
      zone = yandex_vpc_subnet.subnet-a.zone
    }
  }

  instance_template {
    platform_id = "standard-v2" # Intel Cascade Lake

    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.subnet-a.id]
      security_group_ids = [yandex_vpc_security_group.k8s-main-sg.id]
    }

    resources {
      memory = 4 # GB
      cores  = 2 # Number of CPU cores.
    }

    boot_disk {
      type = "network-hdd"
      size = 32 # GB
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = yandex_kubernetes_cluster.k8s-cluster.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.k8s-cluster.master[0].cluster_ca_certificate
    token = var.iam_token
  }
}

resource "helm_release" "cert-manager" {
  namespace        = "cert-manager"
  create_namespace = true
  name             = "jetstack"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.9.1"
  wait             = true
  depends_on = [
    yandex_kubernetes_node_group.k8s-node-group
  ]
  set {
    name  = "installCRDs"
    value = true
  }
}