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

