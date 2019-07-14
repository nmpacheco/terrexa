

variable "environment_tag" {
  type = string
}
variable "location" {
  type = string
}
variable "k8s_cluster_name" {
  type = string
}
variable "control_ids" {
  type = list
}
variable "worker_ids" {
  type = list
}
variable "address_spaces" {
  type = list
}
variable "subnets" {
  type = list
}
variable "podCIDR" {
  type = string
}
variable "control_base_ip" {
  type = number
}
variable "worker_base_ip" {
  type = number
}
variable "ssh_pub_key" {
  type = string
}
variable "ssh_priv_key" {
  type = string
}
variable "control_prefix" {
  type = string
}
variable "worker_prefix" {
  type = string
}
variable "subscription_id" {
  type = string
}
variable "client_id" {
  type = string
}
variable "client_secret" {
  type = string
}
variable "tenant_id" {
  type = string
}


provider "azurerm" {
  version         = "~> 1.30"
  subscription_id = "${var.subscription_id}"
  client_id       = "${var.client_id}"
  client_secret   = "${var.client_secret}"
  tenant_id       = "${var.tenant_id}"
}


resource "azurerm_resource_group" "rgK8s" {
  name     = "rgK8s"
  location = var.location
  tags = {
    environment = var.environment_tag
  }
}

resource "azurerm_virtual_network" "vnetsK8s" {
  name                = "vnetsK8s"
  address_space       = var.address_spaces
  location            = var.location
  resource_group_name = azurerm_resource_group.rgK8s.name
  tags = {
    environment = var.environment_tag
  }
}

resource "azurerm_subnet" "subnetK8s" {
  count                = "${length(var.subnets)}"
  name                 = "${lookup(var.subnets[count.index], "name")}"
  resource_group_name  = "${azurerm_resource_group.rgK8s.name}"
  virtual_network_name = "${azurerm_virtual_network.vnetsK8s.name}"
  address_prefix       = "${lookup(var.subnets[count.index], "prefix")}"
}

resource "azurerm_network_security_group" "secGrpK8s" {
  name                = "secGrpK8s"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "API-Server"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = {
    environment = "${var.environment_tag}"
  }
}

resource "azurerm_public_ip" "controlPubIPK8s" {
  count               = "${length(var.control_ids)}"
  name                = "controlPubIPK8s${var.control_base_ip + count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.control_prefix}${var.control_base_ip + var.control_ids[count.index]}-pub"
  tags = {
    environment = "${var.environment_tag}"
  }
}

resource "azurerm_public_ip" "workerPubIPK8s" {
  count               = "${length(var.worker_ids)}"
  name                = "workerPubIPK8s${var.worker_base_ip + count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.worker_prefix}${var.worker_base_ip + var.worker_ids[count.index]}-pub"
  tags = {
    environment = "${var.environment_tag}"
  }
}

resource "azurerm_public_ip" "pubIPK8sCluster" {
  name                = "pubIPK8sCluster"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  allocation_method   = "Static"
  domain_name_label   = "clusterk8s-pub"
  tags = {
    environment = "${var.environment_tag}"
  }
}

resource "azurerm_lb" "lbK8s" {
  name                = "lbK8s"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  frontend_ip_configuration {
    name                 = "PublicIPAddressK8s"
    public_ip_address_id = "${azurerm_public_ip.pubIPK8sCluster.id}"
  }
}

resource "azurerm_lb_backend_address_pool" "lbBckPoolK8s" {
  name                = "lbBckPoolK8s"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  loadbalancer_id     = "${azurerm_lb.lbK8s.id}"
}

resource "azurerm_network_interface" "vnicsControlSrvK8s" {
  count                     = "${length(var.control_ids)}"
  name                      = "vnicsControlSrvK8s${var.control_base_ip + count.index}"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.rgK8s.name}"
  network_security_group_id = "${azurerm_network_security_group.secGrpK8s.id}"
  enable_ip_forwarding      = true
  ip_configuration {
    name                          = "vnicsControlSrvConfigK8s"
    subnet_id                     = "${element(azurerm_subnet.subnetK8s.*.id, 0)}"
    private_ip_address_allocation = "Static"
    private_ip_address            = "${cidrhost("${element(azurerm_subnet.subnetK8s.*.address_prefix, 0)}", var.control_base_ip + count.index)}"
    public_ip_address_id          = "${element(azurerm_public_ip.controlPubIPK8s.*.id, count.index)}"
  }
  tags = {
    environment = "${var.environment_tag}"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "bckAddrPoolAssocK8s" {
  count                   = "${length(var.control_ids)}"
  network_interface_id    = "${azurerm_network_interface.vnicsControlSrvK8s[count.index].id}"
  ip_configuration_name   = "vnicsControlSrvConfigK8s"
  backend_address_pool_id = "${azurerm_lb_backend_address_pool.lbBckPoolK8s.id}"
}


resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = "${azurerm_resource_group.rgK8s.name}"
  }
  byte_length = 8
}

resource "azurerm_storage_account" "stgAccountK8s" {
  name                     = "diagk8s${random_id.randomId.hex}"
  resource_group_name      = "${azurerm_resource_group.rgK8s.name}"
  location                 = "${var.location}"
  account_replication_type = "LRS"
  account_tier             = "Standard"
  tags = {
    environment = "${var.environment_tag}"
  }
}


resource "azurerm_network_interface" "vnicsWorkerSrvK8s" {
  count                     = "${length(var.control_ids)}"
  name                      = "vnicsWorkerSrvK8s${var.worker_base_ip + count.index}"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.rgK8s.name}"
  network_security_group_id = "${azurerm_network_security_group.secGrpK8s.id}"
  enable_ip_forwarding      = true
  ip_configuration {
    name                          = "vnicsWorkerSrvConfigK8s"
    subnet_id                     = "${element(azurerm_subnet.subnetK8s.*.id, 0)}"
    private_ip_address_allocation = "Static"
    private_ip_address            = "${cidrhost("${element(azurerm_subnet.subnetK8s.*.address_prefix, 0)}", var.worker_base_ip + count.index)}"
    public_ip_address_id          = "${element(azurerm_public_ip.workerPubIPK8s.*.id, count.index)}"
  }
  tags = {
    environment = "${var.environment_tag}"
  }
}

module "files" {
  source             = "./files"
  subnets            = "${var.subnets}"
  podCIDR            = "${var.podCIDR}"
  k8s_cluster_name   = "${var.k8s_cluster_name}"
  control_ids        = "${var.control_ids}"
  control_base_ip    = "${var.control_base_ip}"
  control_prefix     = "${var.control_prefix}"
  worker_ids         = "${var.worker_ids}"
  worker_base_ip     = "${var.worker_base_ip}"
  worker_private_ips = "${azurerm_network_interface.vnicsWorkerSrvK8s}"
  worker_public_ips  = "${azurerm_public_ip.workerPubIPK8s}"
  worker_prefix      = "${var.worker_prefix}"
  cluster_public_ip  = "${azurerm_public_ip.pubIPK8sCluster.ip_address}"
}

module "controllers" {
  source                          = "./controllers"
  location                        = "${var.location}"
  resource_group_name             = "${azurerm_resource_group.rgK8s.name}"
  environment_tag                 = "${var.environment_tag}"
  k8s_cluster_name                = "${var.k8s_cluster_name}"
  control_ids                     = "${var.control_ids}"
  control_base_ip                 = "${var.control_base_ip}"
  control_prefix                  = "${var.control_prefix}"
  network_interfaces              = "${azurerm_network_interface.vnicsControlSrvK8s}"
  ssh_pub_key                     = "${var.ssh_pub_key}"
  ssh_priv_key                    = "${var.ssh_priv_key}"
  hostsFilename                   = "${module.files.hostsFilename}"
  boot_diag_stgAcc                = "${azurerm_storage_account.stgAccountK8s}"
  ca_pem                          = "${module.files.ca_pem}"
  ca_key_pem                      = "${module.files.ca_key_pem}"
  kubernetes_pem                  = "${module.files.kubernetes_pem}"
  kubernetes_key_pem              = "${module.files.kubernetes_key_pem}"
  service_account_pem             = "${module.files.service_account_pem}"
  service_account_key_pem         = "${module.files.service_account_key_pem}"
  admin_pem                       = "${module.files.admin_pem}"
  admin_key_pem                   = "${module.files.admin_key_pem}"
  kube_controller_manager_pem     = "${module.files.kube_controller_manager_pem}"
  kube_controller_manager_key_pem = "${module.files.kube_controller_manager_key_pem}"
  kube_proxy_pem                  = "${module.files.kube_proxy_pem}"
  kube_proxy_key_pem              = "${module.files.kube_proxy_key_pem}"
  kube_scheduler_pem              = "${module.files.kube_scheduler_pem}"
  kube_scheduler_key_pem          = "${module.files.kube_scheduler_key_pem}"

  #  kube_admin_config                     = "${module.files.kube_admin_config}"
  #  kube_controller_manager_config        = "${module.files.kube_controller_manager_config}"
  #  kube_scheduler_config                 = "${module.files.kube_scheduler_config}"
  encryption_config                     = "${module.files.encryption_config}"
  etcd_service_file                     = "${module.files.etcd_service_file}"
  etcd_test_file                        = "${module.files.etcd_test_file}"
  kube_apiserver_service_file           = "${module.files.kube_apiserver_service_file}"
  api_test_file                         = "${module.files.api_test_file}"
  kube_controller_manager_service_file  = "${module.files.kube_controller_manager_service_file}"
  kube_scheduler_yaml_file              = "${module.files.kube_scheduler_yaml_file}"
  kube_scheduler_service_file           = "${module.files.kube_scheduler_service_file}"
  system_kube_apiserver_to_kubelet_file = "${module.files.system_kube_apiserver_to_kubelet_file}"
  system_kube_apiserver_file            = "${module.files.system_kube_apiserver_file}"
  cluster_public_ip                     = "${azurerm_public_ip.pubIPK8sCluster.ip_address}"
}

resource "azurerm_lb_probe" "lbprobeK8sAPI" {
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  loadbalancer_id     = "${azurerm_lb.lbK8s.id}"
  name                = "lbprobeK8sAPI"
  port                = 6443
  protocol            = "Tcp"
}

resource "azurerm_lb_rule" "lbruleK8sAPI" {
  location                       = "${var.location}"
  resource_group_name            = "${azurerm_resource_group.rgK8s.name}"
  loadbalancer_id                = "${azurerm_lb.lbK8s.id}"
  name                           = "lbruleK8sAPI"
  protocol                       = "Tcp"
  frontend_port                  = 6443
  backend_port                   = 6443
  frontend_ip_configuration_name = "PublicIPAddressK8s"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.lbBckPoolK8s.id}"
  probe_id                       = "${azurerm_lb_probe.lbprobeK8sAPI.id}"
}

# depends_on because dynamic public ip is only allocated when assigned a resource (vm or lb)
resource "null_resource" "verifyKubeVersion" {
  provisioner "local-exec" {
    command = "curl --cacert ${module.files.ca_pem} https://${azurerm_public_ip.pubIPK8sCluster.ip_address}:6443/version "
  }
  depends_on = [module.controllers.controllers_done]
}

module "workers" {
  source              = "./workers"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  environment_tag     = "${var.environment_tag}"
  k8s_cluster_name    = "${var.k8s_cluster_name}"
  worker_ids          = "${var.worker_ids}"
  worker_base_ip      = "${var.worker_base_ip}"
  worker_prefix       = "${var.worker_prefix}"
  network_interfaces  = "${azurerm_network_interface.vnicsWorkerSrvK8s}"
  ssh_pub_key         = "${var.ssh_pub_key}"
  ssh_priv_key        = "${var.ssh_priv_key}"
  hostsFilename       = "${module.files.hostsFilename}"
  boot_diag_stgAcc    = "${azurerm_storage_account.stgAccountK8s}"
  ca_pem              = "${module.files.ca_pem}"
  worker_pem          = "${module.files.worker_pem}"
  worker_key_pem      = "${module.files.worker_key_pem}"
  admin_pem           = "${module.files.admin_pem}"
  admin_key_pem       = "${module.files.admin_key_pem}"
  kube_proxy_pem      = "${module.files.kube_proxy_pem}"
  kube_proxy_key_pem  = "${module.files.kube_proxy_key_pem}"
  #  kubelet_config              = "${module.files.kubelet_config}"
  #  kube_proxy_config           = "${module.files.kube_proxy_config}"
  f10_bridge_conf_file        = "${module.files.f10_bridge_conf_file}"
  f99_loopback_conf_file      = "${module.files.f99_loopback_conf_file}"
  containerd_config_toml_file = "${module.files.containerd_config_toml_file}"
  containerd_service_file     = "${module.files.containerd_service_file}"
  kubelet_config_yaml_file    = "${module.files.kubelet_config_yaml_file}"
  kubelet_service_file        = "${module.files.kubelet_service_file}"
  kube_proxy_config_yaml_file = "${module.files.kube_proxy_config_yaml_file}"
  kube_proxy_service_file     = "${module.files.kube_proxy_service_file}"
  proxy_test_file             = "${module.files.proxy_test_file}"
  cluster_public_ip           = "${azurerm_public_ip.pubIPK8sCluster.ip_address}"
  # passing controllers to enforce dependency 
  controllers_done = "${module.controllers.controllers_done}"
}
resource "azurerm_route_table" "routeTableK8s" {
  name                = "routeTableK8s"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  tags = {
    environment = "${var.environment_tag}"
  }
}

resource "azurerm_route" "routesK8s" {
  count                  = "${length(var.worker_ids)}"
  resource_group_name    = "${azurerm_resource_group.rgK8s.name}"
  route_table_name       = "${azurerm_route_table.routeTableK8s.name}"
  name                   = "routeK8s${count.index}"
  address_prefix         = "${cidrsubnet(var.podCIDR, 8, var.worker_base_ip + count.index)}"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = "${azurerm_network_interface.vnicsWorkerSrvK8s[count.index].private_ip_address}"
}


resource "azurerm_subnet_route_table_association" "test" {
  count          = "${length(var.worker_ids)}"
  subnet_id      = "${azurerm_subnet.subnetK8s[0].id}"
  route_table_id = "${azurerm_route_table.routeTableK8s.id}"
}

resource "null_resource" "kubectlConfig" {
  provisioner "local-exec" {
    command = <<EOT
kubectl config set-cluster ${var.k8s_cluster_name} \
--certificate-authority=files/ca.pem \
--embed-certs=true \
--server=https://${azurerm_public_ip.pubIPK8sCluster.ip_address}:6443
kubectl config set-credentials admin \
--client-certificate=files/admin.pem \
--client-key=files/admin-key.pem
kubectl config set-context ${var.k8s_cluster_name} \
--cluster=${var.k8s_cluster_name} \
--user=admin
kubectl config use-context ${var.k8s_cluster_name}
kubectl get componentstatuses
kubectl get nodes
EOT
  }
  depends_on = [module.controllers.controllers_done, module.workers.workers_done]
}

resource "null_resource" "deployDNSCluster" {
  provisioner "local-exec" {
    command = <<EOT
kubectl apply -f https://raw.githubusercontent.com/ivanfioravanti/kubernetes-the-hard-way-on-azure/master/deployments/coredns.yaml
kubectl get pods -l k8s-app=kube-dns -n kube-system
EOT
  }
  depends_on = [null_resource.kubectlConfig]
}

# will have to switch to Kubernetes provider...

resource "null_resource" "verifyCluster" {
  provisioner "local-exec" {
    command = <<EOT
kubectl run --generator=run-pod/v1 busybox --image=busybox:1.28 --command -- sleep 3600
sleep 60
kubectl get pods -l run=busybox
export POD_NAME=$(kubectl get pods -l run=busybox -o jsonpath="{.items[0].metadata.name}")
kubectl exec -i $POD_NAME -- nslookup kubernetes
EOT
  }
  depends_on = [null_resource.deployDNSCluster]
}

resource "null_resource" "createSecret" {
  provisioner "local-exec" {
    command = <<EOT
kubectl create secret generic test-secret \
  --from-literal="mykey=mydata"
ssh -i k8s_key -o StrictHostKeyChecking=no ${var.control_prefix}${var.control_base_ip + var.control_ids[0]}-pub.${var.location}.cloudapp.azure.com \
"ETCDCTL_API=3 etcdctl get /registry/secrets/default/test_secret | hexdump -C"
kubectl delete secret test-secret
EOT
  }
  depends_on = [null_resource.verifyCluster]
}

resource "null_resource" "createPod" {
  provisioner "local-exec" {
    command = <<EOT
kubectl run --generator=run-pod/v1 nginx --image=nginx
sleep 60
kubectl get pods -l run=nginx
export POD_NAME=$(kubectl get pods -l run=nginx -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $POD_NAME 8080:80 &
sleep 10
curl --head http://127.0.0.1:8080
kubectl logs $POD_NAME
kubectl exec -i $POD_NAME -- nginx -v
kubectl expose pod nginx --port 80 --type NodePort
EOT
  }
  depends_on = [null_resource.verifyCluster]
}

data "external" "nodePort" {
  program = ["/bin/bash", "${module.files.get_nodeport_file}"]
  depends_on = [null_resource.createPod]
}

resource "azurerm_network_security_rule" "nginx_port" {
  name = "nginx_port"
  priority = 3000
  direction = "Inbound"
  access = "Allow"
  protocol = "Tcp"
  source_port_range = "*"
  destination_port_range = "${data.external.nodePort.result.port}"
  source_address_prefix = "*"
  destination_address_prefix = "*"
  resource_group_name = "${azurerm_resource_group.rgK8s.name}"
  network_security_group_name = "${azurerm_network_security_group.secGrpK8s.name}"
  depends_on = [null_resource.createPod]
}


resource "null_resource" "testConnectPod" {
  provisioner "local-exec" {
    command = <<EOT
export POD_NAME=$(kubectl get pods -l run=nginx -o jsonpath="{.items[0].metadata.name}")
curl -I http://${var.worker_prefix}${var.worker_base_ip + var.worker_ids[0]}-pub.${var.location}.cloudapp.azure.com:${data.external.nodePort.result.port}
kubectl delete pods  $POD_NAME
EOT
  }
  depends_on = [azurerm_network_security_rule.nginx_port]
}

# [Dashboard local URL](http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/

resource "null_resource" "deployDashboard" {
  provisioner "local-exec" {
    command = <<EOT
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml
kubectl create serviceaccount dashboard -n default
kubectl create clusterrolebinding dashboard-admin -n default --clusterrole=cluster-admin --serviceaccount=default:dashboard
kubectl get secret $(kubectl get serviceaccount dashboard -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 --decode
kubectl proxy
EOT
  }
  depends_on = [null_resource.verifyCluster]
}
