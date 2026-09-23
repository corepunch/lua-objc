#!/bin/bash
set -euo pipefail

bench_tmp_dir=$(mktemp -d)
trap 'rm -rf "$bench_tmp_dir"' EXIT
swiftc -O -module-cache-path "$bench_tmp_dir/cache" \
	benchmarks/swiftui_list.swift -o "$bench_tmp_dir/swiftui-list"

for row_count in 1000 5000; do
	for variant in eager list; do
		printf 'lua-objc %s %s\n' "$variant" "$row_count"
		LUA_OBJC_BENCH_KIND="$variant" LUA_OBJC_BENCH_ROWS="$row_count" \
			/usr/bin/time -l ./lua-objc --test benchmarks/list.lua 2>&1 |
			awk '/eager VStack|native List|maximum resident set size/'
	done
	for variant in eager lazy list; do
		printf 'SwiftUI %s %s\n' "$variant" "$row_count"
		SWIFTUI_BENCH_KIND="$variant" SWIFTUI_BENCH_ROWS="$row_count" \
			/usr/bin/time -l "$bench_tmp_dir/swiftui-list" 2>&1 |
			awk '/SwiftUI|maximum resident set size/'
	done
done
