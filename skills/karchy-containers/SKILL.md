---
name: karchy-containers
description: Use on a karchy system when running, building, listing, stopping or debugging containers with rootless Podman, the `docker` command (podman-docker) or `docker compose` and `podman compose`, or when the task touches `DOCKER_HOST`, `podman.socket`, `$XDG_RUNTIME_DIR/podman/podman.sock`, `/etc/subuid` and `/etc/subgid`, GPU containers with the NVIDIA driver (`nvidia-container-toolkit`, `--device nvidia.com/gpu=all`), the `karchy containers` command (`karchy-containers`), the Containers bar panel or window, or adding and removing the Containers feature (`karchy-feature-containers`, package `karchy-containers`). Do not use for virtual machines (use karchy-vms), or to set up a rootful Docker daemon, which this feature replaces.
---

# karchy containers

The Containers feature is rootless Podman. The `docker` command is Podman (`podman-docker`), and Compose is `docker-compose` talking to the user's Podman socket. There is no Docker daemon, no `docker` group and no `sudo` in everyday use. Write commands as the user would for Docker, and expect Podman's behavior where the two differ.

## Change rules

Follow the change rules in the `karchy` skill. Running, starting, stopping and restarting a container, pulling an image and `compose up` are small changes: do them, then say what changed. These count as large, so describe them and get the user's agreement first:

- Removing volumes, for example `podman volume rm`, `compose down -v` or `podman system reset`.
- Pruning: `karchy containers prune` runs `system prune --force` with no question.
- Removing containers or images the user did not ask about.
- Adding or removing the feature, and anything else that needs `sudo`.
- Running a container with `sudo` or as a rootful Podman. Rootful containers are a separate store that the panel and `docker` do not show.

## Check the feature first

```bash
karchy-feature-containers status    # installed | available
karchy containers engine            # podman or docker; fails when neither is installed
echo "$DOCKER_HOST"                 # unix:///run/user/<uid>/podman/podman.sock
systemctl --user is-active podman.socket
```

If the status is `available`, the user adds it from Quick install › System › Containers (`karchy quick-install window @system`), or with `karchy quick-install install containers` in a terminal. The install uses `sudo`. It refuses when the real `docker` package is installed, because `podman-docker` conflicts with it. In that case the panel and `karchy containers` already work with Docker as the engine, and this skill's Podman details do not apply.

Removing it (`karchy quick-install remove containers`) stops running containers, then asks whether to delete the user's containers, images and volumes. Kept data stays in `~/.local/share/containers`.

## What the package sets up

| What | Where |
| --- | --- |
| `DOCKER_HOST` for every session | `/usr/lib/environment.d/50-karchy-containers.conf` |
| The Podman API socket, enabled for every user | `/usr/lib/systemd/user/sockets.target.wants/podman.socket` |
| Compose banner off | `/usr/share/containers/containers.conf.d/50-karchy.conf` |
| podman-docker's "Emulate Docker CLI" notice off | `/etc/containers/nodocker` |
| What the install added for this user | `/var/lib/karchy/feature-containers` |

These files belong to the package. Do not edit them. Put the user's own Podman settings in `~/.config/containers/`.

The install step also gives the user subordinate ID ranges in `/etc/subuid` and `/etc/subgid` when they have none, then runs `podman system migrate`.

## Traps

- A terminal that was already open when the feature was installed has no `DOCKER_HOST` until the user signs in again. Compose then fails to reach a Docker daemon. Set it for one command: `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock docker compose up -d`.
- The socket starts Podman's service only when something connects. If it is not listening, run `systemctl --user start podman.socket`. Do not enable or start a system-wide `podman.socket` or `docker.service`.
- Use full image names, such as `docker.io/library/nginx`. karchy adds no registry settings, so a short name resolves only if the stock Podman configuration knows it. The feature's own test command is `docker run --rm docker.io/library/hello-world`.
- A rootless container cannot publish a host port below 1024. Publish a high port, for example `-p 8080:80`. Changing `net.ipv4.ip_unprivileged_port_start` is a system change under the large-change rule.
- A published port is open on the host, but the firewall (ufw) denies incoming connections by default. Reaching it from another machine needs a firewall rule, which is a large change.
- If a container reports "newuidmap" or "not enough IDs" errors, check that the user has a line in both `/etc/subuid` and `/etc/subgid`. After any change to them, run `podman system migrate`.
- Files a container writes to a bind mount belong to a subordinate ID on the host. Use `podman unshare` to inspect or fix them, or run the container with `--userns=keep-id`. Do not `sudo chown` the folder as a first step.
- Containers stop when the user's last session ends unless lingering is on. Enabling lingering (`loginctl enable-linger`) is the user's decision.

## GPU containers

GPU containers need the NVIDIA driver from karchy (`karchy-nvidia`). When that package is present, the feature's install step adds `nvidia-container-toolkit`. The toolkit's own `nvidia-cdi-refresh` units write the device spec at `/var/run/cdi/nvidia.yaml` at boot and after driver updates. karchy adds no hook of its own.

```bash
podman run --rm --device nvidia.com/gpu=all <image> nvidia-smi
```

- If the device is not found, check that `/var/run/cdi/nvidia.yaml` exists. It is written once the driver module is loaded, so a restart after installing the driver may be needed. `sudo systemctl start nvidia-cdi-refresh.service` writes it now.
- Use the `--device nvidia.com/gpu=...` form. Docker's `--gpus` flag and the `nvidia` runtime setting are for a Docker daemon.
- If `karchy-nvidia` was installed after the feature, the toolkit is missing. Install the feature again from Quick install, which adds it.

## The karchy containers command

`karchy containers` (the same program as `karchy-containers`) is what the panel and window call. It answers in one JSON shape for Podman and for Docker. Its header in `/usr/share/karchy/bin/karchy-containers` documents the shapes.

```bash
karchy containers list              # every container and Compose project, as JSON
karchy containers summary           # running containers only
karchy containers images
karchy containers logs <container> [lines]
karchy containers start|stop|restart|remove <container>
karchy containers compose up|down|restart <project>
karchy containers forget <project>
karchy containers open [container]  # the Containers window
```

- For ordinary work use `podman`, `docker` and `docker compose` directly. Use `karchy containers` to read state as JSON or to act on a Compose project by name from any folder.
- Compose projects are found from the labels Compose puts on containers. Their folder and files are remembered in `~/.local/state/karchy/containers/projects.json`, so `compose up <project>` works after `down`. `forget` drops a project from that file and does nothing to containers.
- `compose up` fails with "compose file … is gone" when the remembered file no longer exists. Start the project from its folder instead.
- A failed action also sends a desktop notification with the last lines of the error.
- `follow` and `open` need the desktop session. `watch` streams events and does not return.

## Panel and window

The bar shows a Containers icon with a count only while containers run. Its panel lists up to six running containers with a run switch and an "Open <port>" action. The window (`karchy containers open`) has stopped containers, Compose projects, images, logs, remove and prune. Both follow container events, so no refresh is needed after a command.

If the icon does not appear after the feature was installed outside Quick install, run `karchy-shell -q karchy.containers refresh`.
