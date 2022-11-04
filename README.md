# LAVA-Tools

This repository holds a collection of scripts and tools to be used together with
the LAVA test execution platform.

## Content

 `worker/lava_recovery_cmd.sh`:

 Used on a worker for image deployment onto a device under test using the recovery deployment type of LAVA.
 Needs a relaiscard to switch the power of the DuT as well as the VBUS of the programming port. It also 
 uses rpiboot to bring the CM into the programming mode to expose the mass storage device to the worker.
