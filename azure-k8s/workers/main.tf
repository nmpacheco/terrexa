
variable "location" {}
variable "resource_group_name" {}
variable "environment_tag" {}
variable "k8s_cluster_name" {}
variable "worker_ids" {}
variable "worker_base_ip" {}
variable "worker_prefix" {}
variable "network_interfaces" {}
variable "ssh_pub_key" {}
variable "ssh_priv_key" {}
variable "hostsFilename" {}
variable "boot_diag_stgAcc" {}
variable "ca_pem" {}
variable "worker_pem" {}
variable "worker_key_pem" {}
variable "admin_pem" {}
variable "admin_key_pem" {}
variable "kube_proxy_pem" {}
variable "kube_proxy_key_pem" {}
variable "f10_bridge_conf_file" {}
variable "f99_loopback_conf_file" {}
variable "containerd_config_toml_file" {}
variable "containerd_service_file" {}
variable "kubelet_config_yaml_file" {}
variable "kubelet_service_file" {}
variable "kube_proxy_config_yaml_file" {}
variable "kube_proxy_service_file" {}
variable "proxy_test_file" {}
variable "cluster_public_ip" {}
# just to enforce dependency
variable "controllers_done" {}

resource "azurerm_availability_set" "workerK8s" {
  name                = "${var.worker_prefix}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group_name}"
  managed             = true
  tags = {
    environment = "${var.environment_tag}"
  }
}

resource "azurerm_virtual_machine" "vmWorkerK8s" {
  count               = "${length(var.worker_ids)}"
  name                = "vm${var.worker_prefix}${var.worker_base_ip + var.worker_ids[count.index]}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group_name}"
  availability_set_id = "${azurerm_availability_set.workerK8s.id}"
  network_interface_ids = [
    "${element(var.network_interfaces.*.id, count.index)}",
  ]
  primary_network_interface_id = "${element(var.network_interfaces.*.id, count.index)}"
  vm_size                      = "Standard_DS1_v2"
  # doesn't allow 'attach' so vm gets removed
  # could create a managed disk but then os_type implies no os_profile and... mess
  # see https://github.com/terraform-providers/terraform-provider-azurerm/issues/734
  # this is good for testing only
  storage_os_disk {
    name              = "workerOsDisk${var.worker_base_ip + count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }
  storage_image_reference {
    offer     = "UbuntuServer"
    publisher = "Canonical"
    sku       = "18.04-LTS"
    version   = "18.04.201906170"
  }
  os_profile {
    computer_name  = "${var.worker_prefix}${var.worker_base_ip + var.worker_ids[count.index]}"
    admin_username = "k8s"
  }
  # previously created a ssh key
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/k8s/.ssh/authorized_keys"
      key_data = "${file("${var.ssh_pub_key}")}"
    }
  }
  connection {
    host        = "${var.worker_prefix}${var.worker_base_ip + var.worker_ids[count.index]}-pub.${var.location}.cloudapp.azure.com"
    type        = "ssh"
    user        = "k8s"
    password    = ""
    private_key = "${file("${var.ssh_priv_key}")}"
  }
  provisioner "file" {
    source      = "${var.hostsFilename}"
    destination = "/tmp/hosts"
  }
  provisioner "file" {
    source      = "${var.ca_pem}"
    destination = "~/ca.pem"
  }
  provisioner "file" {
    source      = "${var.worker_pem[count.index]}"
    destination = "~/${basename(var.worker_pem[count.index])}"
  }
  provisioner "file" {
    source      = "${var.worker_key_pem[count.index]}"
    destination = "~/${basename(var.worker_key_pem[count.index])}"
  }
  provisioner "file" {
    source      = "${var.admin_pem}"
    destination = "~/admin.pem"
  }
  provisioner "file" {
    source      = "${var.admin_key_pem}"
    destination = "~/admin-key.pem"
  }
  provisioner "file" {
    source      = "${var.kube_proxy_pem}"
    destination = "~/kube-proxy.pem"
  }
  provisioner "file" {
    source      = "${var.kube_proxy_key_pem}"
    destination = "~/kube-proxy-key.pem"
  }
  provisioner "file" {
    source      = "${var.f10_bridge_conf_file[count.index]}"
    destination = "~/10-bridge.conf"
  }
  provisioner "file" {
    source      = "${var.f99_loopback_conf_file}"
    destination = "~/99-loopback.conf"
  }
  provisioner "file" {
    source      = "${var.containerd_config_toml_file}"
    destination = "~/containerd-config.toml"
  }
  provisioner "file" {
    source      = "${var.containerd_service_file}"
    destination = "~/containerd.service"
  }
  provisioner "file" {
    source      = "${var.kubelet_config_yaml_file[count.index]}"
    destination = "~/kubelet-config.yaml"
  }
  provisioner "file" {
    source      = "${var.kubelet_service_file}"
    destination = "~/kubelet.service"
  }
  provisioner "file" {
    source      = "${var.kube_proxy_config_yaml_file}"
    destination = "~/kube-proxy-config.yaml"
  }
  provisioner "file" {
    source      = "${var.kube_proxy_service_file}"
    destination = "~/kube-proxy.service"
  }
  provisioner "file" {
    source      = "${var.proxy_test_file}"
    destination = "~/proxy.test.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/hosts /etc/hosts",
      "sudo apt-get update",
      "sudo apt-get -y install socat conntrack ipset",
      "wget -q --show-progress --https-only --timestamping https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.14.0/crictl-v1.14.0-linux-amd64.tar.gz",
      "wget -q --show-progress --https-only --timestamping https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc",
      "wget -q --show-progress --https-only --timestamping https://github.com/opencontainers/runc/releases/download/v1.0.0-rc8/runc.amd64",
      "wget -q --show-progress --https-only --timestamping https://github.com/containernetworking/plugins/releases/download/v0.8.1/cni-plugins-linux-amd64-v0.8.1.tgz",
      "wget -q --show-progress --https-only --timestamping https://github.com/containerd/containerd/releases/download/v1.2.7/containerd-1.2.7.linux-amd64.tar.gz",
      "wget -q --show-progress --https-only --timestamping https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/kubectl",
      "wget -q --show-progress --https-only --timestamping https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/kube-proxy",
      "wget -q --show-progress --https-only --timestamping https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/kubelet",
      "sudo mkdir -p /etc/cni/net.d /opt/cni/bin /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /var/run/kubernetes",
      "sudo mv runc.amd64 runc",
      "chmod +x kubectl kube-proxy kubelet runc runsc",
      "sudo mv kubectl kube-proxy kubelet runc runsc /usr/local/bin/",
      "sudo tar -xvf crictl-v1.14.0-linux-amd64.tar.gz -C /usr/local/bin/",
      "sudo tar -xvf cni-plugins-linux-amd64-v0.8.1.tgz -C /opt/cni/bin/",
      "sudo tar -xvf containerd-1.2.7.linux-amd64.tar.gz -C /",
      "kubectl config set-cluster ${var.k8s_cluster_name} --certificate-authority=ca.pem --embed-certs=true --server=https://${var.cluster_public_ip}:6443 --kubeconfig=kubeconfig",
      "kubectl config set-credentials system:node:${var.worker_prefix}${var.worker_ids[count.index]} --client-certificate=${basename(var.worker_pem[count.index])} --client-key=${basename(var.worker_key_pem[count.index])} --embed-certs=true --kubeconfig=kubeconfig",
      "kubectl config set-context default --cluster=${var.k8s_cluster_name} --user=system:node:${var.worker_prefix}${var.worker_ids[count.index]} --kubeconfig=kubeconfig",
      "kubectl config use-context default --kubeconfig=kubeconfig",
      "kubectl config set-cluster ${var.k8s_cluster_name} --certificate-authority=ca.pem --embed-certs=true --server=https://${var.cluster_public_ip}:6443 --kubeconfig=kube-proxy.kubeconfig",
      "kubectl config set-credentials kube-proxy --client-certificate=kube-proxy.pem --client-key=kube-proxy-key.pem --embed-certs=true --kubeconfig=kube-proxy.kubeconfig",
      "kubectl config set-context default --cluster=${var.k8s_cluster_name} --user=kube-proxy --kubeconfig=kube-proxy.kubeconfig",
      "kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig",
      "sudo cp -p 10-bridge.conf /etc/cni/net.d/10-bridge.conf",
      "sudo cp -p 99-loopback.conf /etc/cni/net.d/99-loopback.conf",
      "sudo mkdir -p /etc/containerd/",
      "sudo cp -p containerd-config.toml /etc/containerd/config.toml",
      "sudo cp -p containerd.service /etc/systemd/system/containerd.service",
      "sudo cp -p ${basename(var.worker_key_pem[count.index])} ${basename(var.worker_pem[count.index])} /var/lib/kubelet/",
      "sudo cp -p kubeconfig /var/lib/kubelet/kubeconfig",
      "sudo cp -p ca.pem /var/lib/kubernetes/",
      "sudo cp -p kubelet-config.yaml /var/lib/kubelet/kubelet-config.yaml",
      "sudo cp -p kubelet.service /etc/systemd/system/kubelet.service",
      "sudo cp -p kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig",
      "sudo cp -p kube-proxy-config.yaml /var/lib/kube-proxy/kube-proxy-config.yaml",
      "sudo cp -p kube-proxy.service /etc/systemd/system/kube-proxy.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable containerd kubelet kube-proxy",
      "sudo systemctl start containerd kubelet kube-proxy",
      "kubectl config set-cluster ${var.k8s_cluster_name} --certificate-authority=ca.pem --embed-certs=true --server=https://${var.cluster_public_ip}:6443",
      "kubectl config set-credentials admin --client-certificate=admin.pem  --client-key=admin-key.pem",
      "kubectl config set-context ${var.k8s_cluster_name} --cluster=${var.k8s_cluster_name} --user=admin",
      "kubectl config use-context ${var.k8s_cluster_name}",
      "chmod 750 ~/proxy.test.sh",
      "~/proxy.test.sh"
    ]
  }
  boot_diagnostics {
    enabled     = "true"
    storage_uri = "${var.boot_diag_stgAcc.primary_blob_endpoint}"
  }
  tags = {
    environment = "${var.environment_tag}"
    type        = "worker"
  }
  depends_on = [var.controllers_done]
}

resource "null_resource" "vmWorkersDone" {
  provisioner "local-exec" {
    command = "echo vmWorkersDone"
  }
  depends_on = [azurerm_virtual_machine.vmWorkerK8s]
}

output "workers_done" {
  value = "${null_resource.vmWorkersDone}"
}
