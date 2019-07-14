
variable "location" {}
variable "resource_group_name" {}
variable "environment_tag" {}
variable "k8s_cluster_name" {}
variable "control_ids" {}
variable "control_base_ip" {}
variable "control_prefix" {}
variable "network_interfaces" {}
variable "ssh_pub_key" {}
variable "ssh_priv_key" {}
variable "hostsFilename" {}
variable "boot_diag_stgAcc" {}
variable "ca_pem" {}
variable "ca_key_pem" {}
variable "kubernetes_pem" {}
variable "kubernetes_key_pem" {}
variable "service_account_pem" {}
variable "service_account_key_pem" {}
variable "admin_pem" {}
variable "admin_key_pem" {}
variable "kube_controller_manager_pem" {}
variable "kube_controller_manager_key_pem" {}
variable "kube_proxy_pem" {}
variable "kube_proxy_key_pem" {}
variable "kube_scheduler_pem" {}
variable "kube_scheduler_key_pem" {}
variable "encryption_config" {}
variable "etcd_service_file" {}
variable "etcd_test_file" {}
variable "kube_apiserver_service_file" {}
variable "api_test_file" {}
variable "kube_controller_manager_service_file" {}
variable "kube_scheduler_yaml_file" {}
variable "kube_scheduler_service_file" {}
variable "system_kube_apiserver_to_kubelet_file" {}
variable "system_kube_apiserver_file" {}
variable "cluster_public_ip" {}

resource "azurerm_availability_set" "controlK8s" {
  name                = "${var.control_prefix}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group_name}"
  managed             = true
  tags = {
    environment = "${var.environment_tag}"
  }
}

resource "azurerm_virtual_machine" "vmControlK8s" {
  count               = "${length(var.control_ids)}"
  name                = "vm${var.control_prefix}${var.control_base_ip + var.control_ids[count.index]}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group_name}"
  availability_set_id = "${azurerm_availability_set.controlK8s.id}"
  network_interface_ids = [
    "${var.network_interfaces[count.index].id}",
  ]
  primary_network_interface_id = "${var.network_interfaces[count.index].id}"
  vm_size                      = "Standard_DS1_v2"
  # doesn't allow 'attach' so vm gets removed
  # could create a managed disk but then os_type implies no os_profile and... mess
  # see https://github.com/terraform-providers/terraform-provider-azurerm/issues/734
  # this is good for testing only
  storage_os_disk {
    name              = "controlOsDisk${var.control_base_ip + count.index}"
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
    computer_name  = "${var.control_prefix}${var.control_base_ip + var.control_ids[count.index]}"
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
    host        = "${var.control_prefix}${var.control_base_ip + var.control_ids[count.index]}-pub.${var.location}.cloudapp.azure.com"
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
    source      = "${var.ca_key_pem}"
    destination = "~/ca-key.pem"
  }
  provisioner "file" {
    source      = "${var.kubernetes_pem}"
    destination = "~/kubernetes.pem"
  }
  provisioner "file" {
    source      = "${var.kubernetes_key_pem}"
    destination = "~/kubernetes-key.pem"
  }
  provisioner "file" {
    source      = "${var.service_account_pem}"
    destination = "~/service-account.pem"
  }
  provisioner "file" {
    source      = "${var.service_account_key_pem}"
    destination = "~/service-account-key.pem"
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
    source      = "${var.kube_controller_manager_pem}"
    destination = "~/kube-controller-manager.pem"
  }
  provisioner "file" {
    source      = "${var.kube_controller_manager_key_pem}"
    destination = "~/kube-controller-manager-key.pem"
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
    source      = "${var.kube_scheduler_pem}"
    destination = "~/kube-scheduler.pem"
  }
  provisioner "file" {
    source      = "${var.kube_scheduler_key_pem}"
    destination = "~/kube-scheduler-key.pem"
  }
  provisioner "file" {
    source      = "${var.encryption_config}"
    destination = "~/encryption-config.yaml"
  }
  provisioner "file" {
    source      = "${var.etcd_service_file[count.index]}"
    destination = "~/etcd.service"
  }
  provisioner "file" {
    source      = "${var.etcd_test_file[count.index]}"
    destination = "~/etcd.test.sh"
  }
  provisioner "file" {
    source      = "${var.kube_apiserver_service_file[count.index]}"
    destination = "~/kube-apiserver.service"
  }
  provisioner "file" {
    source      = "${var.api_test_file}"
    destination = "~/api.test.sh"
  }
  provisioner "file" {
    source      = "${var.kube_controller_manager_service_file}"
    destination = "~/kube-controller-manager.service"
  }
  provisioner "file" {
    source      = "${var.kube_scheduler_yaml_file}"
    destination = "~/kube-scheduler.yaml"
  }
  provisioner "file" {
    source      = "${var.kube_scheduler_service_file}"
    destination = "~/kube-scheduler.service"
  }
  provisioner "file" {
    source      = "${var.system_kube_apiserver_to_kubelet_file}"
    destination = "~/system:kube-apiserver-to-kubelet"
  }
  provisioner "file" {
    source      = "${var.system_kube_apiserver_file}"
    destination = "~/system:kube-apiserver"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/hosts /etc/hosts",
      "wget -q --show-progress --https-only --timestamping https://github.com/coreos/etcd/releases/download/v3.3.13/etcd-v3.3.13-linux-amd64.tar.gz",
      "tar -xvf etcd-v3.3.13-linux-amd64.tar.gz",
      "sudo mv etcd-v3.3.13-linux-amd64/etcd* /usr/local/bin/",
      "sudo mkdir -p /etc/etcd /var/lib/etcd",
      "sudo cp -p ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/",
      "sudo cp -p etcd.service /etc/systemd/system/",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable etcd",
      "sudo systemctl start etcd",
      "chmod +x ~/etcd.test.sh",
      "~/etcd.test.sh",
      "sudo mkdir -p /etc/kubernetes/config",
      "wget -q --show-progress --https-only --timestamping https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/kube-apiserver",
      "wget -q --show-progress --https-only --timestamping https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/kube-controller-manager",
      "wget -q --show-progress --https-only --timestamping https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/kube-scheduler",
      "wget -q --show-progress --https-only --timestamping https://storage.googleapis.com/kubernetes-release/release/v1.15.0/bin/linux/amd64/kubectl",
      "chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl",
      "sudo cp -p kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/",
      "sudo mkdir -p /var/lib/kubernetes/",
      "sudo cp -p ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem /var/lib/kubernetes/",
      "sudo cp -p service-account-key.pem service-account.pem encryption-config.yaml /var/lib/kubernetes/",
      "sudo cp -p kube-apiserver.service /etc/systemd/system/kube-apiserver.service",
      "kubectl config set-cluster ${var.k8s_cluster_name} --certificate-authority=ca.pem --embed-certs=true --server=https://127.0.0.1:6443 --kubeconfig=kube-controller-manager.kubeconfig",
      "kubectl config set-credentials system:kube-controller-manager --client-certificate=kube-controller-manager.pem --client-key=kube-controller-manager-key.pem --embed-certs=true --kubeconfig=kube-controller-manager.kubeconfig",
      "kubectl config set-context default --cluster=${var.k8s_cluster_name} --user=system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig",
      "kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig",
      "sudo cp -p kube-controller-manager.kubeconfig /var/lib/kubernetes/",
      "sudo cp -p kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service",
      "kubectl config set-cluster ${var.k8s_cluster_name} --certificate-authority=ca.pem --embed-certs=true --server=https://127.0.0.1:6443 --kubeconfig=kube-scheduler.kubeconfig",
      "kubectl config set-credentials system:kube-scheduler --client-certificate=kube-scheduler.pem --client-key=kube-scheduler-key.pem --embed-certs=true --kubeconfig=kube-scheduler.kubeconfig",
      "kubectl config set-context default --cluster=${var.k8s_cluster_name} --user=system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig",
      "kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig",
      "sudo cp -p kube-scheduler.kubeconfig /var/lib/kubernetes/",
      "kubectl config set-cluster ${var.k8s_cluster_name} --certificate-authority=ca.pem --embed-certs=true --server=https://127.0.0.1:6443 --kubeconfig=admin.kubeconfig",
      "kubectl config set-credentials admin --client-certificate=admin.pem --client-key=admin-key.pem --embed-certs=true --kubeconfig=admin.kubeconfig",
      "kubectl config set-context default --cluster=${var.k8s_cluster_name} --user=admin --kubeconfig=admin.kubeconfig",
      "kubectl config use-context default --kubeconfig=admin.kubeconfig",
      "sudo cp -p kube-scheduler.yaml /etc/kubernetes/config/kube-scheduler.yaml",
      "sudo cp -p kube-scheduler.service /etc/systemd/system/kube-scheduler.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler",
      "sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler",
      "kubectl config set-cluster ${var.k8s_cluster_name} --certificate-authority=ca.pem --embed-certs=true --server=https://${var.cluster_public_ip}:6443",
      "kubectl config set-credentials admin --client-certificate=admin.pem  --client-key=admin-key.pem",
      "kubectl config set-context ${var.k8s_cluster_name} --cluster=${var.k8s_cluster_name} --user=admin",
      "kubectl config use-context ${var.k8s_cluster_name}",
      "sleep 30",
      "chmod +x ~/api.test.sh",
      "~/api.test.sh",
      "if [ ${count.index} -eq 0 ]; then kubectl apply -f system:kube-apiserver-to-kubelet; fi",
      "if [ ${count.index} -eq 0 ]; then kubectl apply -f system:kube-apiserver; fi",
    ]
  }
  boot_diagnostics {
    enabled     = "true"
    storage_uri = "${var.boot_diag_stgAcc.primary_blob_endpoint}"
  }
  tags = {
    environment = "${var.environment_tag}"
    type        = "controller"
  }
}

resource "null_resource" "vmControllersDone" {
  provisioner "local-exec" {
    command = "echo vmControllersDone"
  }
  depends_on = [azurerm_virtual_machine.vmControlK8s]
}

output "controllers_done" {
  value = "${null_resource.vmControllersDone}"
}
