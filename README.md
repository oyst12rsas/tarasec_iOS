# TaraSec for iOS

This repository is the public iOS port of the TaraSec App.

The primary implementation and source of truth is the Android-based [TaraSec_App](https://github.com/oyst12rsas/TaraSec_App) repository. New features, protocol changes, security improvements, and behavioural fixes must be implemented and validated in `TaraSec_App` first. They can then be copied or ported to this iOS repository while preserving the same API contracts and behaviour.

The iOS version is currently an early scaffold and may lag behind the primary implementation. Contributions are welcome, but cross-platform changes should begin in `TaraSec_App` so the two clients do not develop incompatible behaviour.
