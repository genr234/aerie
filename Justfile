#!/usr/bin/env just --justfile

zig := env_var_or_default("ZIG", ".tools/zig-aarch64-macos-0.16.0/zig")

build:
  {{zig}} build --summary all

run:
  {{zig}} build run

test:
  {{zig}} build test
