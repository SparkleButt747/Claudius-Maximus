# Task Pattern Library

Quick-reference for common task patterns encountered in Harbor benchmarks.
When the agent identifies a task category, it should follow the corresponding pattern.

## Software Engineering (largest category, ~20%)

### Compilation from source
1. Read README/Makefile/CMakeLists first
2. Install build deps: `apt-get install -y build-essential cmake`
3. For C/C++: `mkdir build && cd build && cmake .. && make -j$(nproc)`
4. For Rust: `cargo build --release`
5. Run resulting binary to verify

### Polyglot / multi-language
1. Identify all languages needed from the instruction
2. Install each runtime
3. Build/run in dependency order
4. Check inter-language interfaces (FFI, pipes, files)

### Interpreter/compiler implementation
1. Read the spec carefully — edge cases matter
2. Start with the simplest possible implementation
3. Test against provided examples first
4. Then handle edge cases

## Debugging (~14%)

### Memory/crash bugs
1. Run the program to reproduce the crash
2. Read the error message (segfault, OOM, etc.)
3. Use `gdb` for C/C++, traceback for Python
4. Common fixes: null checks, buffer sizes, memory allocation
5. Fix and re-run

### Concurrency bugs
1. Look for shared state, locks, race conditions
2. Add proper synchronization
3. Test under load if possible

### Configuration errors
1. Check config file syntax (YAML/JSON/TOML)
2. Verify paths exist
3. Check permissions
4. Validate against schema if available

## Data Science / ETL (~9%)

1. Check data format: CSV, JSON, Parquet, SQLite
2. Install pandas, numpy if needed
3. Read the data first: `head`, `wc -l`, schema check
4. Transform as instructed
5. Verify output format matches expected

## Machine Learning (~7%)

1. Check for GPU: `nvidia-smi` (usually unavailable)
2. Plan for CPU: small batches, few epochs
3. Install: `pip install torch torchvision` or `tensorflow`
4. For inference: load model, run prediction, save output
5. For training: use provided data, match hyperparams from instruction

## Security / Crypto (~6%)

### Cryptanalysis
1. Identify the cipher/algorithm
2. Check for known weaknesses (padding oracle, ECB mode, weak keys)
3. Tools: `openssl`, `pycryptodome`, `gmpy2`, `z3-solver`
4. Common attacks: frequency analysis, known-plaintext, brute force small keyspace

### Reverse engineering
1. `file <binary>` to identify format
2. `strings <binary>` for quick wins
3. `objdump -d` or `ghidra` for disassembly
4. Look for hardcoded strings, keys, passwords

### CVE exploitation
1. Identify the vulnerable software version
2. Search for exploit patterns in provided code
3. Craft input to trigger the vulnerability
4. Capture the flag/output

## System Administration (~5%)

1. Check init system: `systemctl` vs `service` vs `rc-service`
2. Check existing configs before overwriting
3. For services: install, configure, start, verify with `curl`/`telnet`
4. For networking: check ports, firewall rules

## Scientific Computing (variable)

1. Install domain-specific tools (biopython, scipy, coq, etc.)
2. Follow the mathematical/scientific specification precisely
3. Numerical precision matters — check tolerances
4. Verify against provided reference values

## Video/Media (~3%)

1. Install ffmpeg: `apt-get install -y ffmpeg`
2. Check input format: `ffprobe <file>`
3. Process as instructed
4. Verify output: `ffprobe <output>`, check duration/format/codec
