# Test harness apps

This directory contains runnable apps used specifically by automated or manual
framework test workflows. Their Lua modules use the `test.<name>` namespace.

Product apps live in `apps/`, demos live in `demo/`, and headless regression
scripts live in `tests/`.

The parity batch entry point is a test harness streamed by the parity tooling.
