# nixos-kvrocks: 为 Kvrocks 提供现代化且可复现的构建

本仓库提供了一个 Nix flake，用于构建和运行 [Apache Kvrocks](https://kvrocks.apache.org/)。它旨在创建可复现的构建，简化开发流程，并与 NixOS 实现无缝集成。

## 目录

- [功能特性](#功能特性)
- [环境准备](#环境准备)
- [快速开始](#快速开始)
  - [构建 Kvrocks](#构建-kvrocks)
  - [运行 Kvrocks](#运行-kvrocks)
- [开发环境](#开发环境)
  - [进入开发 Shell](#进入开发-shell)
- [NixOS 集成](#nixos-集成)
  - [系统配置](#系统配置)
  - [部署为服务](#部署为服务)
- [自动化](#自动化)
  - [更新依赖](#更新依赖)

## 功能特性

- **可复现构建**: 保证每次构建都产生完全相同的结果。
- **NixOS 模块**: 通过声明式配置将 Kvrocks 部署为 systemd 服务。
- **跨平台支持**: 支持在 `x86_64-linux`、`aarch64-linux`、`x86_64-darwin` 和 `aarch64-darwin` 上构建。
- **优化的依赖管理**: 依赖项被提前获取和预构建，以确保可靠性和速度。
- **完全离线构建**: 首次获取依赖后，构建过程无需网络连接。
- **自动更新**: 提供脚本以自动更新 Kvrocks 及其依赖项。

## 环境准备

确保您的系统中已安装 Nix，并启用了 flake 支持。

请参考 [Nix 官方安装指南](https://nixos.org/download.html)。

## 快速开始

项目被打包为一个 Nix Flake，提供了多种输出。

### 构建 Kvrocks

要编译项目，请在项目根目录中执行 `nix build` 命令。

```shell
nix build
```

此命令会构建 `kvrocks` 包。输出是当前目录下的一个名为 `result` 的符号链接，指向 Nix store 中的构建产物。

```shell
./result/bin/kvrocks --version
```

### 运行 Kvrocks

要直接编译并运行 `kvrocks`，请使用 `nix run`。

```shell
nix run
```

在 `--` 之后传递的任何参数都将转发给 `kvrocks` 可执行文件。

```shell
nix run -- --help
```

## 开发环境

为了方便开发，项目通过 `nix develop` 提供了一个可复现的 shell 环境。

### 进入开发 Shell

该 shell 包含了所有必需的依赖和构建工具。

```shell
nix develop
```

在此 shell 中，您可以使用标准的 Nix 构建阶段。由于项目的复杂性，不建议使用标准的 `cmake` 工作流。您可以改用 `buildPhase` 来触发重新构建。

```shell
# 在 nix develop 环境中
buildPhase
```

## NixOS 集成

对于 NixOS 用户，Kvrocks 可以集成到系统配置中。

### 系统配置

将此 Flake 添加到 NixOS 配置的 `inputs` 中。

```nix
# /etc/nixos/flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kvrocks.url = "github:js0-dep/nixos-kvrocks"; # 或您的本地路径
  };

  outputs = { self, nixpkgs, kvrocks, ... }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            kvrocks.packages.${pkgs.system}.default
          ];
        })
        # ... 其他模块
      ];
    };
  };
}
```

然后，重建系统。

```shell
sudo nixos-rebuild switch --flake .#your-hostname
```

### 部署为服务

该 Flake 提供了一个 NixOS 模块，用于将 Kvrocks 部署为 systemd 服务。

要启用该服务，请将模块添加到您的系统配置中：

```nix
# /etc/nixos/flake.nix
{
  inputs = {
    # ...
    kvrocks.url = "github:js0-dep/nixos-kvrocks";
  };

  outputs = { self, nixpkgs, kvrocks, ... }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      modules = [
        kvrocks.nixosModules.kvrocks
        # ... 其他模块
      ];
    };
  };
}
```

然后，在您的配置中启用该服务：

```nix
# /etc/nixos/configuration.nix
{
  services.kvrocks.enable = true;
}
```

#### 配置

您可以使用 `services.kvrocks.settings` 选项来配置 `kvrocks.conf`。键是与 `kvrocks.conf` 中配置键对应的字符串。

```nix
# /etc/nixos/configuration.nix
{
  services.kvrocks.enable = true;
  services.kvrocks.settings = {
    port = 6667;
    workers = 16;
    "rocksdb.write_buffer_size" = 256;
  };
}
```

对于更复杂的配置，您可以使用 `services.kvrocks.configFile` 选项直接提供一个完整的 `kvrocks.conf` 文件。

```nix
# /etc/nixos/configuration.nix
{
  services.kvrocks.enable = true;
  services.kvrocks.configFile = ./my-kvrocks.conf;
}
```

## 自动化

本仓库包含用于自动化依赖更新的脚本。

### 更新依赖

`update.js` 脚本会检查 Kvrocks 及其依赖的最新版本，更新 `dep.json`、`sha.json` 和 `ver.json` 文件，并格式化代码。

要运行更新脚本：

```shell
./update.js
```