# Frustration Log

## 2026-08-05: Restricted simulator compile has no runtime

`make sim-compile` can fail during asset catalog compilation when the
restricted environment cannot connect to CoreSimulator or discover an iOS
Simulator runtime. Use the host-side `make test` path for verification when
available; it successfully built and ran the unit tests in this environment.
