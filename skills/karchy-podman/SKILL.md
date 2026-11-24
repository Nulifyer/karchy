---
name: karchy-podman
description: Use on a karchy system that has karchy's Podman setup (package `karchy-podman`, Quick install › System › Podman) when running, building, stopping or debugging containers with rootless Podman, the `docker` command (podman-docker) or `docker compose` and `podman compose`, or when the task touches `DOCKER_HOST`, `podman.socket`, `$XDG_RUNTIME_DIR/podman/podman.sock`, `/etc/subuid` and `/etc/subgid`, GPU containers with the NVIDIA driver (`nvidia-container-toolkit`, `--device nvidia.com/gpu=all`), or adding and removing the setup (`karchy-feature-podman`). Do not use for the Containers window and the `karchy containers` command (use karchy-containers), for virtual machines (use karchy-vms), or to set up a rootful Docker daemon, which this setup replaces.
---

# karchy's Podman setup

karchy's Podman setup is rootless Podman. The `docker` command is Podman (`podman-docker`), and Compose is `docker-compose` talking to the user's Podman socket. There is no Docker daemon, no `docker` group and no `sudo` in everyday use. Write commands as the user would for Docker, and expect Podman's behavior where the two differ.

This skill is installed with the setup (package `karchy-podman`). The Containers window is a separate app, `karchy-containers-app`, with its own skill, `karchy-containers`. Neither needs the other. A machine can also have Docker instead of this setup, or Podman installed by hand without it; then this skill is absent and its details do not apply.

## Change rules

Follow the change rules in the `karchy` skill. Running, starting, stopping and restarting a container, pulling an image and `compose up` are small changes: do them, then say what changed. These count as large, so describe them and get the user's agreement first:

- Removing volumes, for example `podman volume rm`, `compose down -v` or `podman system reset`.
- Pruning, for example `podman system prune`.
- Removing containers or images the user did not ask about.
- Adding or removing the setup, and anything else that needs `sudo`.
- Running a container with `sudo` or as a rootful Podman. Rootful containers are a separate store that `docker` and the Containers window do not show.

## Check the setup first

```bash
karchy-feature-podman status        # installed | available
echo "$DOCKER_HOST"                 # unix:///run/user/<uid>/podman/podman.sock
systemctl --user is-active podman.socket
```

If the status is `available`, the user adds it from Quick install › System › Podman (`karchy quick-install window podman`), or with `karchy quick-install install podman` in a terminal. The install uses `sudo`. It refuses when the real `docker` package is installed, because `podman-docker` conflicts with it; for the same reason Quick install refuses Docker while this setup is installed, and says so. The user chooses one: remove the other first.

Removing it (`karchy quick-install remove podman`) stops running containers, then asks whether to delete the user's containers, images and volumes. Kept data stays in `~/.local/share/containers`. The Containers app, if installed, stays.

## What the package sets up

| What | Where |
| --- | --- |
| `DOCKER_HOST` for every session | `/usr/lib/environment.d/50-karchy-podman.conf` |
| The Podman API socket, enabled for every user | `/usr/lib/systemd/user/sockets.target.wants/podman.socket` |
| Compose banner off | `/usr/share/containers/containers.conf.d/50-karchy.conf` |
| podman-docker's "Emulate Docker CLI" notice off | `/etc/containers/nodocker` |
| What the install added for this user | `/var/lib/karchy/feature-podman` |

These files belong to the package. Do not edit them. Put the user's own Podman settings in `~/.config/containers/`.

The install step also gives the user subordinate ID ranges in `/etc/subuid` and `/etc/subgid` when they have none, then runs `podman system migrate`.

## Traps

- A terminal that was already open when the setup was installed has no `DOCKER_HOST` until the user signs in again. Compose then fails to reach a Docker daemon. Set it for one command: `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock docker compose up -d`.
- The socket starts Podman's service only when something connects. If it is not listening, run `systemctl --user start podman.socket`. Do not enable or start a system-wide `podman.socket` or `docker.service`.
- Use full image names, such as `docker.io/library/nginx`. karchy adds no registry settings, so a short name resolves only if the stock Podman configuration knows it. The setup's own test command is `docker run --rm docker.io/library/hello-world`.
- A rootless container cannot publish a host port below 1024. Publish a high port, for example `-p 8080:80`. Changing `net.ipv4.ip_unprivileged_port_start` is a system change under the large-change rule.
- A published port is open on the host, but the firewall (ufw) denies incoming connections by default. Reaching it from another machine needs a firewall rule, which is a large change.
- If a container reports "newuidmap" or "not enough IDs" errors, check that the user has a line in both `/etc/subuid` and `/etc/subgid`. After any change to them, run `podman system migrate`.
- Files a container writes to a bind mount belong to a subordinate ID on the host. Use `podman unshare` to inspect or fix them, or run the container with `--userns=keep-id`. Do not `sudo chown` the folder as a first step.
- Containers stop when the user's last session ends unless lingering is on. Enabling lingering (`loginctl enable-linger`) is the user's decision.

## GPU containers

GPU containers need the NVIDIA driver from karchy (`karchy-nvidia`). When that package is present, the setup's install step adds `nvidia-container-toolkit`. The toolkit's own `nvidia-cdi-refresh` units write the device spec at `/var/run/cdi/nvidia.yaml` at boot and after driver updates. karchy adds no hook of its own.

```bash
podman run --rm --device nvidia.com/gpu=all <image> nvidia-smi
```

- If the device is not found, check that `/var/run/cdi/nvidia.yaml` exists. It is written once the driver module is loaded, so a restart after installing the driver may be needed. `sudo systemctl start nvidia-cdi-refresh.service` writes it now.
- Use the `--device nvidia.com/gpu=...` form. Docker's `--gpus` flag and the `nvidia` runtime setting are for a Docker daemon.
- If `karchy-nvidia` was installed after the setup, the toolkit is missing. Run `karchy quick-install install podman` again in a terminal, which adds it.

## Seeing what runs

`podman ps -a` and `docker ps -a` list the same containers. With the Containers app installed, `karchy containers list` gives them as JSON and the window and bar panel show them; see the `karchy-containers` skill.
