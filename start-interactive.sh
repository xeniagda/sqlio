#!/bin/sh
set -e
cargo build
sqlite3 :memory: -cmd '.load target/debug/libsqlio'
