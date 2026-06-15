# Kustomize 最小学习例子

这个例子展示 Kustomize 最核心的用法：

- `base/` 放通用 Kubernetes YAML
- `overlays/dev/` 和 `overlays/prod/` 复用 base
- overlay 通过 patch 修改不同环境的副本数和镜像 tag

## 目录结构

```text
.
├── base
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays
    ├── dev
    │   ├── kustomization.yaml
    │   └── patch-replicas.yaml
    └── prod
        ├── kustomization.yaml
        └── patch-replicas.yaml
```

## 试运行

如果你装了 `kubectl`：

```powershell
kubectl kustomize .\overlays\dev
kubectl kustomize .\overlays\prod
```

如果你单独装了 `kustomize`：

```powershell
kustomize build .\overlays\dev
kustomize build .\overlays\prod
```

## 应用到集群

```powershell
kubectl apply -k .\overlays\dev
```

生产环境示例：

```powershell
kubectl apply -k .\overlays\prod
```

## 安装 flannel

如果 Pod 一直卡在 `ContainerCreating`，并且事件里有类似：

```text
failed to load flannel 'subnet.env' file: open /run/flannel/subnet.env: no such file or directory
```

说明集群的 flannel CNI 没正常安装或没正常运行。可以执行：

```powershell
.\scripts\install-flannel.ps1
```

跳过确认提示：

```powershell
.\scripts\install-flannel.ps1 -Yes
```

安装后检查：

```powershell
kubectl get pods -n kube-flannel -o wide
kubectl get nodes -o wide
kubectl get pods -n demo-dev
```

Ubuntu/Linux 环境使用：

```bash
chmod +x scripts/install-flannel.sh
./scripts/install-flannel.sh
```

跳过确认提示：

```bash
AUTO_YES=true ./scripts/install-flannel.sh
```

## Ubuntu 安装最新版 Kubernetes

脚本会先卸载旧的 `kubelet`、`kubeadm`、`kubectl`，再按 Kubernetes 官方 `pkgs.k8s.io` 仓库安装最新 stable 版本。

```bash
sudo bash scripts/install-latest-k8s-ubuntu.sh
```

跳过确认提示：

```bash
AUTO_YES=true sudo -E bash scripts/install-latest-k8s-ubuntu.sh
```

只安装组件，不执行 `kubeadm init`：

```bash
INIT_CLUSTER=false sudo -E bash scripts/install-latest-k8s-ubuntu.sh
```

## 你应该观察什么

`dev` 输出里：

- namespace 是 `demo-dev`
- Deployment 名字带 `dev-` 前缀
- replicas 是 `1`
- nginx 镜像 tag 是 `1.27`

`prod` 输出里：

- namespace 是 `demo-prod`
- Deployment 名字带 `prod-` 前缀
- replicas 是 `3`
- nginx 镜像 tag 是 `1.27-alpine`
