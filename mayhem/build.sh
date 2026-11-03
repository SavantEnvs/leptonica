#!/usr/bin/env bash
#
# mayhem/build.sh — build leptonica's fuzz harnesses (all of prog/fuzzing/*_fuzzer.cc, the OSS-Fuzz
# set), their -standalone reproducers, and the regression/known-answer suite that mayhem/test.sh runs.
#
# Runs in the commit image as `mayhem` in /mayhem (base ENV: CC, CXX, SANITIZER_FLAGS,
# LIB_FUZZING_ENGINE, STANDALONE_FUZZ_MAIN). Re-runnable and offline: image-installed -dev packages
# only, build dirs are /mayhem/build-* (gitignored upstream via /build*).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS SRC

cd "$SRC"

# Same macro OSS-Fuzz builds with: upstream's own guard refusing absurd pixCreate() sizes (>64MB, >20K side).
FUZZ_DEFS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
SYSLIBS="-lgif -ljpeg -lopenjp2 -lpng -ltiff -lwebp -lwebpmux -lz -lm"

# 1) Sanitized + coverage-instrumented library (static), with DWARF<=3.
LIBFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $FUZZ_DEFS"
cmake -S "$SRC" -B "$SRC/build-fuzz" -G Ninja \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_PROG=OFF \
    -DCMAKE_C_FLAGS="$LIBFLAGS" -DCMAKE_CXX_FLAGS="$LIBFLAGS" \
    -DCMAKE_C_FLAGS_RELEASE="-O1" -DCMAKE_CXX_FLAGS_RELEASE="-O1" \
    -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS"
cmake --build "$SRC/build-fuzz" -j"$MAYHEM_JOBS" --target leptonica
LEPTLIB="$SRC/build-fuzz/src/libleptonica.a"
[ -f "$LEPTLIB" ] || { echo "missing $LEPTLIB" >&2; exit 1; }

# 2) Harnesses: fuzzer binary + -standalone reproducer, both with LSan off at build time.
OBJ="$SRC/build-fuzz/obj"
mkdir -p "$OBJ"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OBJ/lsan_off.o"

build_harness() {
    local f="$1" name
    name="$(basename "$f" .cc)"
    local inc="-I$SRC/src -I$SRC/build-fuzz/src -I$SRC/prog/fuzzing"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_DEFS $inc $LIB_FUZZING_ENGINE \
        "$f" "$OBJ/lsan_off.o" "$LEPTLIB" $SYSLIBS -o "$SRC/$name"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_DEFS $inc \
        "$f" "$OBJ/standalone_main.o" "$OBJ/lsan_off.o" "$LEPTLIB" $SYSLIBS -o "$SRC/$name-standalone"
}
export -f build_harness
export FUZZ_DEFS SYSLIBS OBJ LEPTLIB
ls "$SRC"/prog/fuzzing/*_fuzzer.cc | xargs -P "$MAYHEM_JOBS" -I{} bash -c 'build_harness {}'

# 3) Test suite with the project's NORMAL flags (no sanitizers, no -gdwarf-3): a separate build tree.
cmake -S "$SRC" -B "$SRC/build-test" -G Ninja \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_PROG=OFF \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS"
cmake --build "$SRC/build-test" -j"$MAYHEM_JOBS" --target leptonica
TESTLIB="$SRC/build-test/src/libleptonica.a"
TESTBIN="$SRC/build-test/bin"
mkdir -p "$TESTBIN"
TINC="-I$SRC/src -I$SRC/build-test/src"

# Regression programs that need neither gnuplot nor extra sources; test.sh runs generate + compare.
REG_TESTS="$(cat "$SRC/mayhem/reg-tests.txt")"
for t in $REG_TESTS; do
    echo "$t"
done | xargs -P "$MAYHEM_JOBS" -I{} \
    $CC -O2 $COVERAGE_FLAGS $TINC "$SRC/prog/{}_reg.c" "$TESTLIB" $SYSLIBS -o "$TESTBIN/{}_reg"
$CC -O2 $COVERAGE_FLAGS $TINC "$SRC/mayhem/kat_probe.c" "$TESTLIB" $SYSLIBS -o "$TESTBIN/kat_probe"
