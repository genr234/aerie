#!/usr/bin/env just --justfile

zig := env_var_or_default("ZIG", ".tools/zig-aarch64-macos-0.16.0/zig")

build:
    {{ zig }} build --summary all

run:
    {{ zig }} build run

test:
    {{ zig }} build test

editor-dev:
    {{ zig }} build --summary all
    export PATH="$(dirname "$(rustup which cargo)"):$PATH"; frontend/node_modules/.bin/tauri dev

editor-build:
    {{ zig }} build --summary all
    export PATH="$(dirname "$(rustup which cargo)"):$PATH"; frontend/node_modules/.bin/tauri build
