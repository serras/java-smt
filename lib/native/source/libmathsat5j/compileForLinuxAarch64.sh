#!/usr/bin/env bash

# This file is part of JavaSMT,
# an API wrapper for a collection of SMT solvers:
# https://github.com/sosy-lab/java-smt
#
# SPDX-FileCopyrightText: 2021 Dirk Beyer <https://www.sosy-lab.org>
#
# SPDX-License-Identifier: Apache-2.0

# #########################################
#
# INFO:
# This script is automatically called from ant when publishing MathSAT5.
# There is no need to call this scripts manually, except for developing and debugging.
#
# #########################################

# This script builds libmathsat5j.so (bindings to mathsat5).

# For building libmathsat5j.so, there are two dependencies:
# - The static Mathsat5 library for ARMv8 (aarch64) can be downloaded
#   from https://mathsat.fbk.eu/release/mathsat-5.6.6-linux-aarch64-reentrant.tar.gz
# - The static GMP library compiled with the "-fPIC" option
#   To create this, download GMP 6.1.2 from http://gmplib.org/ and run:
#   - cross-compiling on Ubuntu x64_86 for ARMv8 (aarch64):
#       export CC=aarch64-linux-gnu-gcc-8 CXX=aarch64-linux-gnu-g++-8 ABI=64
#       ./configure --enable-cxx --with-pic --disable-shared --enable-fat --host=aarch64-linux-gnueabi
#       make
#   - alternative: direct compilation on the Raspi (slow!):
#       ./configure --enable-cxx --with-pic --disable-shared --enable-fat
#       make

# To build mathsat bindings: ./compileForLinuxAarch64.sh $MATHSAT_DIR $GMP_DIR
# We cross-compile the bindings on Ubuntu x64_86 for ARMv8 (aarch64).

# This script searches for all included libraries in the current directory first.
# You can use this to override specific libraries installed on your system.
# You can also use this to force static linking of a specific library,
# if you put only the corresponding .a file in this directory, not the .so file.

# For example, to statically link against libstdc++,
# compile this library with --with-pic,
# and put the resulting libstdc++.a file in this directory.

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ ${SOURCE} != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

cd ${DIR}

JNI_HEADERS="$(../get_jni_headers.sh)"

MSAT_SRC_DIR="$1"/include
MSAT_LIB_DIR="$1"/lib
GMP_LIB_DIR="$2"/.libs
GMP_HEADER_DIR="$2"

SRC_FILES="org_sosy_1lab_java_1smt_solvers_mathsat5_Mathsat5NativeApi.c"
OBJ_FILES="org_sosy_1lab_java_1smt_solvers_mathsat5_Mathsat5NativeApi.o"

# check requirements
if [ ! -f "$MSAT_LIB_DIR/libmathsat.a" ]; then
    echo "You need to specify the directory with the downloaded Mathsat on the command line!"
    exit 1
fi
if [ ! -f "$GMP_LIB_DIR/libgmp.a" ]; then
    echo "You need to specify the GMP directory on the command line!"
    echo "Can not find $GMP_LIB_DIR/libgmp.a"
    exit 1
fi

OUT_FILE="libmathsat5j-aarch64.so"
ADDITIONAL_FLAGS=""

GCC="aarch64-linux-gnu-gcc-8" # cross-compiling for ARMv8 (aarch64)
# for ARMv7 (32bit) use "arm-linux-gnueabihf-gcc"
# for direct compilation use "gcc"

echo "Compiling the C wrapper code and creating the \"$OUT_FILE\" library..."

# This will compile the JNI wrapper part, given the JNI and the Mathsat header files
$GCC -g -std=gnu99 -Wall -Wextra -Wpedantic -Wno-return-type -Wno-unused-parameter $JNI_HEADERS -I$MSAT_SRC_DIR -I$GMP_HEADER_DIR $SRC_FILES -fPIC -c $ADDITIONAL_FLAGS

echo "Compilation Done"
echo "Linking libraries together into one file..."

# This will link together the file produced above, the Mathsat library, the GMP library and the standard libraries.
# Everything except the standard libraries is included statically.
# The result is a single shared library containing all necessary components.
$GCC -Wall -g -o ${OUT_FILE} -shared -Wl,-soname,libmathsat5j.so \
    -L. -L${MSAT_LIB_DIR} -L${GMP_LIB_DIR} -I${GMP_HEADER_DIR} ${OBJ_FILES} \
    -Wl,-Bstatic -lmathsat -lgmpxx -lgmp -static-libstdc++ -lstdc++ \
    -Wl,-Bdynamic -lc -lm

if [ $? -ne 0 ]; then
    echo "There was a problem during compilation of \"org_sosy_1lab_java_1smt_solvers_mathsat5_Mathsat5NativeApi.c\""
    exit 1
fi

echo "Linking Done"
# TODO The tool strip seems to fail for for "ELF 64-bit LSB shared object, ARM aarch64"
# and reports "unrecognized file format for *.so".
# This does not further influence the build process.
# echo "Reducing file size by dropping unused symbols..."

# strip ${OUT_FILE}

# echo "Reduction Done"

MISSING_SYMBOLS="$(readelf -Ws ${OUT_FILE} | grep NOTYPE | grep GLOBAL | grep UND)"
if [ ! -z "$MISSING_SYMBOLS" ]; then
    echo "Warning: There are the following unresolved dependencies in libmathsat5j.so:"
    readelf -Ws ${OUT_FILE} | grep NOTYPE | grep GLOBAL | grep UND
    exit 1
fi

echo "All Done"
