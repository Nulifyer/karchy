# NVIDIA early KMS and hibernation (2026-11-16)

Question: with the open modules (595+, CachyOS ships 620.70.06) loaded in the initramfs (early KMS), does resume from hibernation still fail? Answer: yes. No module option, temp-file path or service fixes it, so karchy turns hibernation off on NVIDIA machines (D-79).

## Mechanism

- On the resume boot the initramfs loads the image, then the NVIDIA driver loaded in that initramfs refuses to freeze its GPU and the kernel boots fresh: `NVRM: … PreserveVideoMemoryAllocations module parameter is set. System Power Management attempted without driver procfs suspend interface.` / `nv_pmops_freeze [nvidia] returns -5` / `PM: hibernation: Failed to load image, recovering.` (https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1343, opened 2026-09-07, open, no NVIDIA reply).
- At tag 620.70.06, `kernel-open/nvidia/nv.c` `nv_pm_notifier()` handles only `PM_SUSPEND_PREPARE`, `PM_HIBERNATION_PREPARE`, `PM_POST_SUSPEND`, `PM_POST_HIBERNATION`; the restore-path events are ignored, and the freeze hits the guard that returns `NV_ERR_NOT_SUPPORTED`.
- The 595+ in-kernel suspend handling (595.45.04 changelog; default since 615.71.09) covers the hibernate side only. The guard fires with the default `PreserveVideoMemoryAllocations: 2` and the NVIDIA services disabled.
- Arch Wiki, NVIDIA: "Early loading the modules will break hibernation, as video memory preservation is enabled by default." Its stated reason (no access to `NVreg_TemporaryFilePath`) doesn't match the code; the conclusion does.

## Still present

Reports in #1343 on 595.104.02, 610.57.04, 615.71.09, 615.78.08 and 620.70.06, across Turing, Ampere, Ada and Blackwell, with mkinitcpio and dracut. CachyOS's chwd adds the same early load and its users hit the same error (https://discuss.cachyos.org/t/system-fails-to-resume-after-hibernation-due-to-nvidia/22527).

## What works

- `PreserveVideoMemoryAllocations=0`: the image restores, then the GPU fails (Xid 31, then Xid 154).
- No NVIDIA module in the initramfs: several clean resumes reported in #1343, with counter-reports (a black screen on a 5090; Xids on a 4080S).
- A hook that unloads the NVIDIA modules only when the swap holds an image (reads the signature at `resume=`/`resume_offset=`, finds `S1SUSPEND`, `rmmod`s before resume) is reported working on 610 and 615 with the busybox initramfs; a systemd-initramfs port is untested.

## Test on the desktop, once a driver says it's fixed

Save everything first: the failure is a fresh boot that loses the session.

1. Record `sort /proc/driver/nvidia/params | grep -E 'Preserve|KernelSuspend|TempFile'`, `lsinitcpio <initramfs> | grep nvidia`, `cat /proc/sys/kernel/random/boot_id`; leave a terminal open with a marker in it.
2. `sudo btrfs inspect-internal map-swapfile -r /swap/swapfile` equals `resume_offset` in `/proc/cmdline`.
3. Allow hibernation for the test: `/etc/systemd/sleep.conf.d/karchy-nvidia.conf` with `[Sleep]` `AllowHibernation=yes`. Then `systemctl hibernate`, power on, unlock.
4. Pass: the marker terminal is back, `boot_id` unchanged, `journalctl -k -b | grep -E 'hibernation exit|nv_pmops|Xid'` shows the exit and no errors, and a GL/Vulkan app runs cleanly after about 2 minutes. Fail: `nv_pmops_freeze … -5` as above.
5. Remove the test file afterwards.
