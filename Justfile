#!/usr/bin/env just --justfile

build:
  zig build --summary all

run:
  zig build run
