[English](#en) | [中文](./readme/zh.md)

---

<a id="en"></a>

# nixos-kvrocks: Modern and reproducible builds for Kvrocks

This repository provides a Nix flake for building and running [Apache Kvrocks](https://kvrocks.apache.org/). It is designed to create reproducible builds, simplify development, and offer seamless integration with NixOS.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Build Kvrocks](#build-kvrocks)
  - [Run Kvrocks](#run-kvrocks)
- [Development](#development)
  - [Entering the Development Shell](#entering-the-development-shell)
- [NixOS Integration](#nixos-integration)
  - [System Configuration](#system-configuration)
  - [Deploying as a Service](#deploying-as-a-service)
- [Automation](#automation)
  - [Updating Dependencies](#updating-dependencies)

## Features

- **Reproducible Builds**: Guarantees that every build produces the exact same result.
- **NixOS Module**: Deploy Kvrocks as a systemd service with declarative configuration.
- **Cross-Platform Support**: Builds on `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, and `aarch64-darwin`.
- **Optimized Dependency Management**: Dependencies are fetched and pre-built to ensure reliability and speed.
- **Fully Disconnected Builds**: After the initial fetch, no network access is required to build.
- **Automatic Updates**: Scripts are provided to automatically update Kvrocks and its dependencies.

## Prerequisites

Ensure Nix is installed on your system with flake support enabled.

Refer to the [official Nix installation guide](https://nixos.org/download.html).

## Quick Start

The project is packaged as a Nix flake, providing several outputs.

### Build Kvrocks

To compile the project, execute the `nix build` command from the project root directory.

```shell
nix build
```

This command builds the `kvrocks` package. The output is a symlink named `result` in the current directory, pointing to the build artifacts in the Nix store.

```shell
./result/bin/kvrocks --version
```

### Run Kvrocks

To compile and run `kvrocks` directly, use `nix run`.

```shell
nix run
```

Any arguments passed after `--` will be forwarded to the `kvrocks` executable.

```shell
nix run -- --help
```

## Development

For development, a reproducible shell is provided via `nix develop`.

### Entering the Development Shell

This shell contains all necessary dependencies and build tools.

```shell
nix develop
```

Inside this shell, you can use standard Nix build phases. Due to the project's complexity, using the standard `cmake` workflow is not recommended. Instead, you can trigger a rebuild using the `buildPhase`.

```shell
# Inside nix develop
buildPhase
```

## NixOS Integration

For users on NixOS, Kvrocks can be integrated into the system configuration.

### System Configuration

Add the flake to your NixOS configuration's `inputs`.

```nix
# /etc/nixos/flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kvrocks.url = "github:js0-dep/nixos-kvrocks"; # Or your local path
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
        # ... other modules
      ];
    };
  };
}
```

Then, rebuild the system.

```shell
sudo nixos-rebuild switch --flake .#your-hostname
```

### Deploying as a Service

The flake provides a NixOS module to deploy Kvrocks as a systemd service.

To enable the service, add the module to your system configuration:

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
        # ... other modules
      ];
    };
  };
}
```

Then, enable the service in your configuration:

```nix
# /etc/nixos/configuration.nix
{
  services.kvrocks.enable = true;
}
```

#### Configuration

You can configure `kvrocks.conf` using the `services.kvrocks.settings` option. The keys are strings corresponding to the configuration keys in `kvrocks.conf`.

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

For more complex configurations, you can provide a full `kvrocks.conf` file directly using the `services.kvrocks.configFile` option.

```nix
# /etc/nixos/configuration.nix
{
  services.kvrocks.enable = true;
  services.kvrocks.configFile = ./my-kvrocks.conf;
}
```

## Automation

This repository includes scripts to automate dependency updates.

### Updating Dependencies

The `update.js` script checks for the latest version of Kvrocks and its dependencies, updates the `dep.json`, `sha.json`, and `ver.json` files, and formats the code.

To run the update script:

```shell
./update.js
```
