# Zig Benchmarks

The Zig rewrite exposes a built-in benchmark command:

```bash
./zig-out/bin/sioyek --bench tutorial.pdf Sioyek 5
```

This measures:

- document open time
- first page size query time
- first page render time
- outline load time
- search time

Use the wrapper script to capture internal timings plus external wall time and memory:

```bash
./benchmarks/run_zig_bench.sh ./zig-out/bin/sioyek tutorial.pdf Sioyek 5
```

The script writes a JSON result file under `benchmarks/results/`.

Notes:

- This is the current Zig-side benchmark harness.
- The Qt baseline is not automated yet because the existing desktop app does not expose the same headless measurement commands.
- The intended comparison model is milestone-to-milestone on the Zig branch now, then Qt-vs-Zig where the same scenario can be driven fairly.
