# Needs cfssl, cfssljson and kubectl in terraform host.
# Note that some dependencies are in place only to force all 
# kubectl's to run in sequence - kubectl lock for config changes

variable "k8s_cluster_name" {}
variable "subnets" {}
variable "podCIDR" {}
variable "control_ids" {}
variable "control_base_ip" {}
variable "control_prefix" {}
variable "worker_ids" {}
variable "worker_base_ip" {}
variable "worker_private_ips" {}
variable "worker_public_ips" {}
variable "worker_prefix" {}
variable "cluster_public_ip" {}

locals {
  hosts = <<EOT
127.0.0.1 localhost

# The following lines are desirable for IPv6 capable hosts
::1 ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
%{for num in var.control_ids~}
${cidrhost(lookup(var.subnets[0], "prefix"), var.control_base_ip + num)} ${var.control_prefix}${var.control_base_ip + num}
%{endfor~}
%{for num in var.worker_ids~}
${cidrhost(lookup(var.subnets[0], "prefix"), var.worker_base_ip + num)} ${var.worker_prefix}${var.worker_base_ip + num}
%{endfor~}
EOT
}

resource "local_file" "hosts" {
  content = "${local.hosts}"
  filename = "${path.module}/hosts"
}

output "hostsFilename" {
  value = "${local_file.hosts.filename}"
}

# Certificate Authority
# this and others could be heredoc style but also ends up jsonencoding
locals {
  ca_config = {
    "signing" = {
      "default" = {
        "expiry" = "8760h"
      },
      "profiles" = {
        "kubernetes" = {
          "usages" = ["signing", "key encipherment", "server auth", "client auth"],
          "expiry" = "8760h"
        }
      }
    }
  }
  ca_csr = {
    "CN" = "Kubernetes",
    "key" = {
      "algo" = "rsa",
      "size" = 2048
    },
    "names" = [
      {
        "C" = "PT",
        "L" = "Lisbon",
        "O" = "Kubernetes",
        "OU" = "myOU",
        "ST" = "Portugal"
      }
    ]
  }
}
resource "local_file" "ca_config" {
  content = "${jsonencode(local.ca_config)}"
  filename = "${path.module}/ca-config.json"
}
resource "local_file" "ca_csr" {
  content = "${jsonencode(local.ca_csr)}"
  filename = "${path.module}/ca-csr.json"
}
resource "null_resource" "genCertAuth" {
  provisioner "local-exec" {
    command = "(cfssl gencert -initca ${local_file.ca_csr.filename} | cfssljson -bare ca; mv ca.pem ca-key.pem ca.csr ${path.module})"
  }
}
output "ca_csr" {
  value = "${local_file.ca_csr.filename}"
}
output "ca_pem" {
  value = "${path.module}/ca.pem"
}
output "ca_key_pem" {
  value = "${path.module}/ca-key.pem"
}

# Client and Server Certificates
locals {
  admin_csr = {
    "CN" = "admin",
    "key" = {
      "algo" = "rsa",
      "size" = 2048
    },
    "names" = [
      {
        "C" = "PT",
        "L" = "Lisbon",
        "O" = "system:masters",
        "OU" = "myOU",
        "ST" = "Portugal"
      }
    ]
  }
}

resource "local_file" "admin_csr" {
  content = "${jsonencode(local.admin_csr)}"
  filename = "${path.module}/admin-csr.json"
}
resource "null_resource" "genAdminCert" {
  provisioner "local-exec" {
    command = "cfssl gencert -ca=${path.module}/ca.pem -ca-key=${path.module}/ca-key.pem -config=${local_file.ca_config.filename} -profile=kubernetes ${local_file.admin_csr.filename} | cfssljson -bare admin; mv admin.pem admin-key.pem admin.csr ${path.module}"
  }
  depends_on = [null_resource.genCertAuth]
}

output "admin_csr" {
  value = "${local_file.admin_csr.filename}"
}
output "admin_pem" {
  value = "${path.module}/admin.pem"
}
output "admin_key_pem" {
  value = "${path.module}/admin-key.pem"
}

locals {
  # could also be heredoc and templating
  # would need additional data template step
  instance_csr = [for num in var.worker_ids :
    {
      "CN" = "system:node:${var.worker_prefix}${var.worker_base_ip + num}"
      "key" = {
        "algo" = "rsa"
        "size" = 2048
      },
      "names" = [
        {
          "C" = "PT"
          "L" = "Lisbon"
          "O" = "system:nodes"
          "OU" = "myOU"
          "ST" = "Portugal"
        }
      ]
    }
  ]
  command_instance_csr = <<EOT
%{for num in var.worker_ids~}
cfssl gencert \
  -ca=${path.module}/ca.pem \
  -ca-key=${path.module}/ca-key.pem \
  -config=${local_file.ca_config.filename} \
  -hostname=${var.worker_prefix}${var.worker_base_ip + num},${var.worker_public_ips[num].ip_address},${var.worker_private_ips[num].private_ip_address} \
  -profile=kubernetes ${path.module}/${var.worker_prefix}${var.worker_base_ip + num}-csr.json | \
  cfssljson -bare ${var.worker_prefix}${var.worker_base_ip + num}
mv ${var.worker_prefix}${var.worker_base_ip + num}.csr ${var.worker_prefix}${var.worker_base_ip + num}.pem ${var.worker_prefix}${var.worker_base_ip + num}-key.pem ${path.module}
%{endfor~}
EOT
}

resource "local_file" "instance_csr" {
  count    = "${length(var.worker_ids)}"
  content  = "${jsonencode(element(local.instance_csr, count.index))}"
  filename = "${path.module}/${var.worker_prefix}${var.worker_base_ip + var.worker_ids[count.index]}-csr.json"
}

resource "null_resource" "genInstanceCert" {
  provisioner "local-exec" {
    command = "${local.command_instance_csr}"
  }
  depends_on = [null_resource.genCertAuth, local_file.instance_csr]
}

output "worker_csr" {
  value = [for num in var.worker_ids : "${path.module}/${var.worker_prefix}${var.worker_base_ip + num}.csr"]
}
output "worker_pem" {
  value = [for num in var.worker_ids : "${path.module}/${var.worker_prefix}${var.worker_base_ip + num}.pem"]
}
output "worker_key_pem" {
  value = [for num in var.worker_ids : "${path.module}/${var.worker_prefix}${var.worker_base_ip + num}-key.pem"]
}

locals {
  kube_controller_manager = {
  "CN" = "system:kube-controller-manager"
  "key" = {
    "algo" = "rsa"
    "size" = 2048
  }
  "names" = [
    {
      "C"  = "PT"
      "L"  = "Lisbon"
      "O"  = "system:kube-controller-manager"
      "OU" = "myOU"
      "ST" = "Portugal"
    }
  ]
}
  command_kube_controller_manager = <<EOT
cfssl gencert \
  -ca=${path.module}/ca.pem \
  -ca-key=${path.module}/ca-key.pem \
  -config=${local_file.ca_config.filename} \
  -profile=kubernetes \
  ${path.module}/kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
mv kube-controller-manager.csr kube-controller-manager.pem kube-controller-manager-key.pem ${path.module}
EOT
}

resource "local_file" "kube_controller_manager_csr" {
  content = "${jsonencode(local.kube_controller_manager)}"
  filename = "${path.module}/kube-controller-manager-csr.json"
}

resource "null_resource" "genKubeControllerManagerCert" {
  provisioner "local-exec" {
    command = "${local.command_kube_controller_manager}"
  }
  depends_on = [null_resource.genCertAuth, local_file.kube_controller_manager_csr]
}

output "kube_controller_manager_csr" {
  value = "${path.module}/kube-controller-manager.csr"
}
output "kube_controller_manager_pem" {
  value = "${path.module}/kube-controller-manager.pem"
}
output "kube_controller_manager_key_pem" {
  value = "${path.module}/kube-controller-manager-key.pem"
}

locals {
  kube_proxy = {
  "CN" = "system:kube-proxy"
  "key" = {
    "algo" = "rsa"
    "size" = 2048
  }
  "names" = [
    {
      "C" = "PT"
      "L" = "Lisbon"
      "O" = "system:node-proxier"
      "OU" = "myOU"
      "ST" = "Portugal"
    }
  ]
}
  command_kube_proxy = <<EOT
cfssl gencert \
  -ca=${path.module}/ca.pem \
  -ca-key=${path.module}/ca-key.pem \
  -config=${local_file.ca_config.filename} \
  -profile=kubernetes \
  ${path.module}/kube-proxy-csr.json | cfssljson -bare kube-proxy
mv kube-proxy.csr kube-proxy.pem kube-proxy-key.pem ${path.module}
EOT
}

resource "local_file" "kube_proxy_csr" {
  content  = "${jsonencode(local.kube_proxy)}"
  filename = "${path.module}/kube-proxy-csr.json"
}

resource "null_resource" "genKubeProxyCert" {
  provisioner "local-exec" {
    command = "${local.command_kube_proxy}"
  }
  depends_on = [null_resource.genCertAuth, local_file.kube_proxy_csr]
}

output "kube_proxy_csr" {
  value = "${path.module}/kube-proxy.csr"
}
output "kube_proxy_pem" {
  value = "${path.module}/kube-proxy.pem"
}
output "kube_proxy_key_pem" {
  value = "${path.module}/kube-proxy-key.pem"
}

locals {
  kube_scheduler = {
    "CN" = "system:kube-scheduler"
    "key" = {
      "algo" = "rsa"
      "size" = 2048
    }
    "names" = [
      {
        "C"  = "PT"
        "L"  = "Lisbon"
        "O"  = "system:kube-scheduler"
        "OU" = "myOU"
        "ST" = "Portugal"
      }
    ]
  }
  command_kube_scheduler = <<EOT
cfssl gencert \
  -ca=${path.module}/ca.pem \
  -ca-key=${path.module}/ca-key.pem \
  -config=${local_file.ca_config.filename} \
  -profile=kubernetes \
  ${path.module}/kube-scheduler-csr.json | cfssljson -bare kube-scheduler
mv kube-scheduler.csr kube-scheduler.pem kube-scheduler-key.pem ${path.module}
EOT
}

resource "local_file" "kube_scheduler_csr" {
  content = "${jsonencode(local.kube_scheduler)}"
  filename = "${path.module}/kube-scheduler-csr.json"
}

resource "null_resource" "genKubeSchedulerCert" {
  provisioner "local-exec" {
    command = "${local.command_kube_scheduler}"
  }
  depends_on = [null_resource.genCertAuth, local_file.kube_scheduler_csr]
}

output "kube_scheduler_csr" {
  value = "${path.module}/kube-scheduler.csr"
}
output "kube_scheduler_pem" {
  value = "${path.module}/kube-scheduler.pem"
}
output "kube_scheduler_key_pem" {
  value = "${path.module}/kube-scheduler-key.pem"
}

locals {
  kubernetes = {
    "CN" = "kubernetes"
    "key" = {
      "algo" = "rsa"
      "size" = 2048
    }
    "names" = [
      {
        "C" = "PT"
        "L" = "Lisbon"
        "O" = "Kubernetes"
        "OU" = "myOU"
        "ST" = "Portugal"
      }
    ]
  }
  list_hostname = join(",", [for num in var.control_ids : cidrhost(lookup(var.subnets[0], "prefix"), var.control_base_ip + num)])
  command_kubernetes = <<EOT
cfssl gencert \
  -ca=${path.module}/ca.pem \
  -ca-key=${path.module}/ca-key.pem \
  -config=${local_file.ca_config.filename} \
  -hostname=10.32.0.1,${local.list_hostname},${var.cluster_public_ip},127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  ${path.module}/kubernetes-csr.json | cfssljson -bare kubernetes
mv kubernetes.csr kubernetes.pem kubernetes-key.pem ${path.module}
EOT
}

resource "local_file" "kubernetes_csr" {
  content  = "${jsonencode(local.kubernetes)}"
  filename = "${path.module}/kubernetes-csr.json"
}

resource "null_resource" "genKubernetesCert" {
  provisioner "local-exec" {
    command = "${local.command_kubernetes}"
  }
  depends_on = [null_resource.genCertAuth, local_file.kubernetes_csr]
}

output "kubernetes_csr" {
  value = "${path.module}/kubernetes.csr"
}
output "kubernetes_pem" {
  value = "${path.module}/kubernetes.pem"
}
output "kubernetes_key_pem" {
  value = "${path.module}/kubernetes-key.pem"
}

locals {
  service_account = {
  "CN" = "service-accounts"
  "key" = {
    "algo" = "rsa"
    "size" : 2048
  }
  "names" = [
    {
      "C"  = "PT"
      "L"  = "Lisbon"
      "O"  = "Kubernetes"
      "OU" = "myOU"
      "ST" = "Portugal"
    }
  ]
}
  command_service_account = <<EOT
cfssl gencert \
  -ca=${path.module}/ca.pem \
  -ca-key=${path.module}/ca-key.pem \
  -config=${local_file.ca_config.filename} \
  -profile=kubernetes \
  ${path.module}/service-account-csr.json | cfssljson -bare service-account
mv service-account.csr service-account.pem service-account-key.pem ${path.module}
EOT
}

resource "local_file" "service_account_csr" {
  content = "${jsonencode(local.service_account)}"
  filename = "${path.module}/service-account-csr.json"
}

resource "null_resource" "genServiceAccountCert" {
  provisioner "local-exec" {
    command = "${local.command_service_account}"
  }
  depends_on = [null_resource.genCertAuth, local_file.service_account_csr]
}

output "service_account_csr" {
  value = "${path.module}/service-account.csr"
}
output "service_account_pem" {
  value = "${path.module}/service-account.pem"
}
output "service_account_key_pem" {
  value = "${path.module}/service-account-key.pem"
}

resource "random_id" "encryption_key" {
  byte_length = 32
}

locals {
  encryption_config = <<EOT
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${random_id.encryption_key.b64_std}
      - identity: {}
EOT
}

resource "local_file" "encryption_config" {
  content  = "${local.encryption_config}"
  filename = "${path.module}/encryption_config.yaml"
}

output "encryption_config" {
  value = "${path.module}/encryption_config.yaml"
}

locals {
  cluster_list = "${join(",", [
    for id in var.control_ids :
  "${var.control_prefix}${var.control_base_ip + id}=https://${cidrhost(lookup(var.subnets[0], "prefix"), var.control_base_ip + id)}:2380"])}"
}

data "template_file" "etcd_service_tpl" {
  count    = "${length(var.control_ids)}"
  template = <<EOT
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \
  --name $${etcd_hostname} \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --peer-cert-file=/etc/etcd/kubernetes.pem \
  --peer-key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth \
  --initial-advertise-peer-urls https://$${internal_ip}:2380 \
  --listen-peer-urls https://$${internal_ip}:2380 \
  --listen-client-urls https://$${internal_ip}:2379,http://127.0.0.1:2379 \
  --advertise-client-urls https://$${internal_ip}:2379 \
  --initial-cluster-token etcd-cluster-0 \
  --initial-cluster ${local.cluster_list} \
  --initial-cluster-state new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
  vars = {
    etcd_hostname = "${var.control_prefix}${var.control_base_ip + var.control_ids[count.index]}"
    internal_ip = "${cidrhost(lookup(var.subnets[0], "prefix"), var.control_base_ip + var.control_ids[count.index])}"
  }
}

resource "local_file" "etcd_service_file" {
  count = "${length(var.control_ids)}"
  content = "${data.template_file.etcd_service_tpl[count.index].rendered}"
  filename = "${path.module}/etcd.service.${var.control_prefix}${var.control_base_ip + var.control_ids[count.index]}"
}

output "etcd_service_file" {
  value = [for num in var.control_ids : "${path.module}/etcd.service.${var.control_prefix}${var.control_base_ip + num}"]
}

locals {
  etcd_list = "${join(",", [
    for id in var.control_ids :
  "https://${cidrhost(lookup(var.subnets[0], "prefix"), var.control_base_ip + id)}:2379"])}"
}

data "template_file" "etcd_test_tpl" {
  count = "${length(var.control_ids)}"
  template = <<EOT
#!/bin/bash
while [[ $(sudo ETCDCTL_API=3 etcdctl member list --endpoints=https://$${internal_ip}:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem|wc -l 2>/dev/null) == 0 ]]
do 
    echo etcd_waiting
    sleep 5
done
EOT
    vars = {
        internal_ip = "${cidrhost(lookup(var.subnets[0], "prefix"), var.control_base_ip + var.control_ids[count.index])}"
    }
}

resource "local_file" "etc_test_file" {
  count    = "${length(var.control_ids)}"
  content  = "${data.template_file.etcd_test_tpl[count.index].rendered}"
  filename = "${path.module}/etcd.test.${var.control_prefix}${var.control_base_ip + var.control_ids[count.index]}.sh"
}

output "etcd_test_file" {
  value = [for num in var.control_ids : "${path.module}/etcd.test.${var.control_prefix}${var.control_base_ip + num}.sh"]
}

data "template_file" "kube_apiserver_service_tpl" {
  count    = "${length(var.control_ids)}"
  template = <<EOT
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
  --advertise-address=$${internal_ip} \
  --allow-privileged=true \
  --apiserver-count=3 \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=3 \
  --audit-log-maxsize=100 \
  --audit-log-path=/var/log/audit.log \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=/var/lib/kubernetes/ca.pem \
  --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,TaintNodesByCondition,Priority,DefaultTolerationSeconds,DefaultStorageClass,PersistentVolumeClaimResize,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota \
  --enable-swagger-ui=true \
  --etcd-cafile=/var/lib/kubernetes/ca.pem \
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \
  --etcd-servers=${local.etcd_list} \
  --event-ttl=1h \
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \
  --kubelet-https=true \
  --runtime-config=api/all \
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \
  --service-cluster-ip-range=10.32.0.0/24 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
  vars = {
    internal_ip = "${cidrhost(lookup(var.subnets[0], "prefix"), var.control_base_ip + var.control_ids[count.index])}"
  }
}

resource "local_file" "kube_apiserver_service" {
  count = "${length(var.control_ids)}"
  content = "${data.template_file.kube_apiserver_service_tpl[count.index].rendered}"
  filename = "${path.module}/kube-apiserver.service.${var.control_prefix}${var.control_base_ip + var.control_ids[count.index]}"
}

output "kube_apiserver_service_file" {
  value = [for num in var.control_ids : "${path.module}/kube-apiserver.service.${var.control_prefix}${var.control_base_ip + num}"]
}

resource "local_file" "kube_controller_manager_service" {
  content = <<EOT
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
  --address=0.0.0.0 \
  --cluster-cidr=${var.podCIDR} \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \
  --leader-elect=true \
  --root-ca-file=/var/lib/kubernetes/ca.pem \
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \
  --service-cluster-ip-range=10.32.0.0/24 \
  --use-service-account-credentials=true \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
  filename = "${path.module}/kube-controller-manager.service"
}

output "kube_controller_manager_service_file" {
  value = "${path.module}/kube-controller-manager.service"
}

resource "local_file" "kube_scheduler_yaml" {
  content = <<EOT
apiVersion: kubescheduler.config.k8s.io/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOT
  filename = "${path.module}/kube-scheduler.yaml"
}

output "kube_scheduler_yaml_file" {
  value = "${path.module}/kube-scheduler.yaml"
}

resource "local_file" "kube_scheduler_service" {
  content = <<EOT
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \
  --config=/etc/kubernetes/config/kube-scheduler.yaml \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
  filename = "${path.module}/kube-scheduler.service"
}

output "kube_scheduler_service_file" {
  value = "${path.module}/kube-scheduler.service"
}

resource "local_file" "system_kube_apiserver_to_kubelet" {
  content = <<EOT
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOT
  filename = "${path.module}/system:kube-apiserver-to-kubelet"
}

output "system_kube_apiserver_to_kubelet_file" {
  value = "${path.module}/system:kube-apiserver-to-kubelet"
}

resource "local_file" "system_kube_apiserver" {
  content = <<EOT
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOT
  filename = "${path.module}/system:kube-apiserver"
}

output "system_kube_apiserver_file" {
  value = "${path.module}/system:kube-apiserver"
}

resource "local_file" "api_test_file" {
  count   = "${length(var.control_ids)}"
  content = <<EOT
#!/bin/bash
echo api_waiting
kubectl get componentstatuses
while [[ $(kubectl get componentstatuses|grep etcd|grep Healthy|wc -l 2>/dev/null) != ${length(var.control_ids)} ]]
do 
  echo api_waiting
  sleep 5
done
EOT
  filename = "${path.module}/api.test.sh"
}

output "api_test_file" {
  value = "${path.module}/api.test.sh"
}

resource "local_file" "f10_bridge_conf" {
  count = "${length(var.worker_ids)}"
  content = <<EOT
{
    "cniVersion": "0.2.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${cidrsubnet(var.podCIDR, 8, var.worker_base_ip + count.index)}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOT
  filename = "${path.module}/10-bridge.conf.${var.worker_prefix}${var.worker_base_ip + var.worker_ids[count.index]}"
}

output "f10_bridge_conf_file" {
  value = [for num in var.worker_ids : "${path.module}/10-bridge.conf.${var.worker_prefix}${var.worker_base_ip + num}"]
}

resource "local_file" "f99_loopback_conf" {
  content = <<EOT
{
    "cniVersion": "0.2.0",
    "name": "lo",
    "type": "loopback"
}
EOT
  filename = "${path.module}/99-loopback.conf"
}

output "f99_loopback_conf_file" {
  value = "${path.module}/99-loopback.conf"
}

resource "local_file" "containerd_config_toml" {
  content = <<EOT
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runsc"
      runtime_root = "/run/containerd/runsc"
    [plugins.cri.containerd.gvisor]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runsc"
      runtime_root = "/run/containerd/runsc"
EOT
  filename = "${path.module}/containerd-config.toml"
}

output "containerd_config_toml_file" {
  value = "${path.module}/containerd-config.toml"
}

resource "local_file" "containerd_service" {
  content = <<EOT
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd

Delegate=yes
KillMode=process
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOT
  filename = "${path.module}/containerd.service"
}

output "containerd_service_file" {
  value = "${path.module}/containerd.service"
}

resource "local_file" "kubelet_config_yaml" {
  count = "${length(var.worker_ids)}"
  content = <<EOT
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
podCIDR: "${var.podCIDR}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${var.worker_prefix}${var.worker_base_ip + var.worker_ids[count.index]}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${var.worker_prefix}${var.worker_base_ip + var.worker_ids[count.index]}-key.pem"
EOT
  filename = "${path.module}/kubelet-config.yaml.${var.worker_prefix}${var.worker_base_ip + var.worker_ids[count.index]}"
}

output "kubelet_config_yaml_file" {
  value = [for num in var.worker_ids : "${path.module}/kubelet-config.yaml.${var.worker_prefix}${var.worker_base_ip + num}"]
}

resource "local_file" "kubelet_service" {
  content = <<EOT
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \
  --config=/var/lib/kubelet/kubelet-config.yaml \
  --container-runtime=remote \
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \
  --image-pull-progress-deadline=2m \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --network-plugin=cni \
  --register-node=true \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
  filename = "${path.module}/kubelet.service"
}

output "kubelet_service_file" {
  value = "${path.module}/kubelet.service"
}

resource "local_file" "kube_proxy_config_yaml" {
  content = <<EOT
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "${var.podCIDR}"
EOT
  filename = "${path.module}/kube-proxy-config.yaml"
}

output "kube_proxy_config_yaml_file" {
  value = "${path.module}/kube-proxy-config.yaml"
}

resource "local_file" "kube_proxy_service" {
  content = <<EOT
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
  filename = "${path.module}/kube-proxy.service"
}

output "kube_proxy_service_file" {
  value = "${path.module}/kube-proxy.service"
}

resource "local_file" "proxy_test_file" {
  content = <<EOT
#!/bin/bash
echo proxy_waiting
kubectl get nodes
while [[ $(kubectl get nodes|wc -l 2>/dev/null) == 0 ]]
do 
  echo proxy_waiting
  sleep 5
done
EOT
  filename = "${path.module}/proxy.test.sh"
}

output "proxy_test_file" {
  value = "${path.module}/proxy.test.sh"
}

resource "local_file" "get_nodeport_file" {
  content = <<EOT
#!/bin/bash
kubectl get svc nginx -o json|jq -r '.spec.ports[0]|{\"port\":.nodePort}'
EOT
  filename = "${path.module}/get_nodeport.sh"
}

output "get_nodeport_file" {
  value = "${path.module}/get_nodeport.sh"
}

