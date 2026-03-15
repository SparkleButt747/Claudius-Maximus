#!/bin/bash
# Claudius-Maximus Environment Bootstrap
# Run this first in any container to map the environment

set -euo pipefail

echo "=== ENVIRONMENT BOOTSTRAP ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# OS Info
echo "--- OS ---"
cat /etc/os-release 2>/dev/null | grep -E "^(NAME|VERSION)" || echo "Unknown OS"
echo "Arch: $(uname -m)"
echo "Kernel: $(uname -r)"
echo ""

# Languages
echo "--- LANGUAGES ---"
for cmd in python3 python node ruby perl php java javac go rustc gcc g++ gfortran cobc ocaml ghc R scheme; do
    if command -v "$cmd" &>/dev/null; then
        ver=$("$cmd" --version 2>&1 | head -1) || ver="(version unknown)"
        echo "  [OK] $cmd: $ver"
    fi
done
echo ""

# Build tools
echo "--- BUILD TOOLS ---"
for cmd in make cmake ninja meson cargo npm pip pip3 yarn pnpm composer bundler mix; do
    if command -v "$cmd" &>/dev/null; then
        ver=$("$cmd" --version 2>&1 | head -1) || ver="(version unknown)"
        echo "  [OK] $cmd: $ver"
    fi
done
echo ""

# System tools
echo "--- SYSTEM TOOLS ---"
for cmd in git docker curl wget ssh scp tar zip unzip jq yq sed awk grep find xargs; do
    if command -v "$cmd" &>/dev/null; then
        echo "  [OK] $cmd"
    fi
done
echo ""

# Security tools
echo "--- SECURITY TOOLS ---"
for cmd in openssl gdb objdump readelf strings binwalk nmap netcat nc xxd file; do
    if command -v "$cmd" &>/dev/null; then
        echo "  [OK] $cmd"
    fi
done
echo ""

# Package managers
echo "--- PACKAGE MANAGERS ---"
if command -v apt-get &>/dev/null; then echo "  [OK] apt-get"; fi
if command -v yum &>/dev/null; then echo "  [OK] yum"; fi
if command -v apk &>/dev/null; then echo "  [OK] apk"; fi
if command -v dnf &>/dev/null; then echo "  [OK] dnf"; fi
if command -v pacman &>/dev/null; then echo "  [OK] pacman"; fi
echo ""

# Python packages (if Python available)
if command -v python3 &>/dev/null; then
    echo "--- PYTHON PACKAGES ---"
    python3 -c "
import sys
packages = ['numpy', 'pandas', 'scipy', 'sklearn', 'torch', 'tensorflow',
            'matplotlib', 'requests', 'flask', 'django', 'fastapi',
            'cryptography', 'pycryptodome', 'gmpy2', 'z3', 'sympy',
            'pytest', 'unittest']
for pkg in packages:
    try:
        mod = __import__(pkg)
        ver = getattr(mod, '__version__', 'unknown')
        print(f'  [OK] {pkg}: {ver}')
    except ImportError:
        pass
" 2>/dev/null
    echo ""
fi

# Working directory
echo "--- WORKING DIRECTORY ---"
echo "CWD: $(pwd)"
echo ""
echo "Files:"
ls -la 2>/dev/null || echo "(empty or no access)"
echo ""

# Check for task files
echo "--- TASK FILES ---"
for f in instruction.md instructions.md README.md task.md; do
    if [ -f "/app/$f" ]; then
        echo "  Found: /app/$f ($(wc -l < "/app/$f") lines)"
    fi
done
if [ -d "/app/tests" ]; then
    echo "  Tests directory found:"
    ls -la /app/tests/ 2>/dev/null
fi
echo ""

# Resources
echo "--- RESOURCES ---"
echo "CPUs: $(nproc 2>/dev/null || echo 'unknown')"
free -h 2>/dev/null | head -2 || echo "Memory: unknown"
df -h / 2>/dev/null | tail -1 || echo "Disk: unknown"
echo ""

# Network
echo "--- NETWORK ---"
if curl -s --max-time 3 http://google.com > /dev/null 2>&1; then
    echo "  Internet: AVAILABLE"
elif wget -q --timeout=3 http://google.com -O /dev/null 2>&1; then
    echo "  Internet: AVAILABLE (wget)"
else
    echo "  Internet: UNAVAILABLE (work offline)"
fi
echo ""

# Environment variables of interest
echo "--- RELEVANT ENV VARS ---"
env | grep -iE "^(PATH|HOME|USER|LANG|LC_|DISPLAY|CUDA|GPU|OPENAI|ANTHROPIC|API)" 2>/dev/null | head -20
echo ""

echo "=== BOOTSTRAP COMPLETE ==="
