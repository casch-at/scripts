#!/bin/bash
# from-scratch.sh --- build libraries/programs from scratch
# Copyright (c) Christian Schwarzgruber <c.schwarzgruber.cs@gmail.com>
# Author: Christian Schwarzgruber
# Created: Mon May  9 18:59:27 2016 (+0200)
# Description: Simple script to compile GCC/LLVM-Clang and other software from
# scratch.
#
set -e # Always fail on error, makes live easier :-)
readonly SCRIPT_NAME=$(basename $0)

### Programs

readonly MAKE=$(which make)
readonly CMAKE=$(which cmake)
readonly GIT=$(which git)

### Handy variables

# shellcheck disable=SC2016
{
readonly CMAKE_BUILD='nice -n 19 $CMAKE --build . -- -j $CORES'
readonly CMAKE_INSTALL_DEBUG='$CMAKE --build . --target install'
readonly CMAKE_INSTALL_RELEASE='$CMAKE --build . --target install/strip'
readonly MAKE_BUILD='nice -n 19 $MAKE -j $CORES'
readonly MAKE_INSTALL='$MAKE install'
}

### Available packages

readonly LIST="llvm_clang gcc rtags gdb"

### Customizable variables

CORES=${CORES-$(grep -c ^processor /proc/cpuinfo)}
BUILD_LIST=${BUILD_LIST-}
BUILD_DIR=${BUILD_DIR-}
INSTALL_PREFIX=${INSTALL_PREFIX-}
GCC_PREFIX=${GCC_PREFIX-$(dirname "$(dirname "$(which gcc)")")}
GCC_LIB_PREFIX=${GCC_LIB_PREFIX-/usr}
GDB_INSTALL_PREFIX=${GDB_INSTALL_PREFIX-$HOME/rtest/gdb}
LLVM_INSTALL_PREFIX=${LLVM_INSTALL_PREFIX-$INSTALL_PREFIX}
CGTOOL=${CGTOOL-Ninja}

### Logic

function usage()
{
    cat<<EOF

    Usage: $SCRIPT_NAME [OPTIONS]

    Simple script to compile various defined libraries/programs.

    --build            Semicolon seperated string of packages in the order they
                       should be build.
    --build-dir        The build directory. (default temporary directory in /tmp)
    --cmake-gen        CMake build generater tool. (default $CGTOOL)
    --gcc-lib-prefix   GCC libraries prefix path. Same as --gcc-prefix if GCC
                       is in the --build list. (default $GCC_LIB_PREFIX)
    --gcc-prefix       GCC install prefix or prefix path to GCC, if gcc isn't in
                       the --build list. (default $GCC_PREFIX)
    --help             Print this help.
    --jobs             How many jobs should be used to build the package.
                       (default $CORES)
    --llvm-prefix      LLVM/Clang installation prefix, defaults to --prefix.
    --llvm-version     The LLVM/Clang version to install.
    --with-lldb        Whether to build LLVM debuger or not (default OFF)
    --prefix           General installation prefix.

    Available packages to build:

      $LIST

EOF
}

TEMP=$(getopt -o - -n $SCRIPT_NAME \
              -l build:,cmake-gen,jobs:,gcc-prefix:,gcc-lib-prefix:,prefix: \
              -l llvm-prefix:,llvm-version:,with-lldb,build-dir:,help \
              -- "$@")

eval set -- "$TEMP"
unset TEMP
while true; do
    case $1 in
        --build) BUILD_LIST=$2; shift 2 ;;
        --cmake-gen) CGTOOL=$2; shift 2 ;;
        --jobs) CORES=$2; shift 2 ;;
        --gcc-prefix) GCC_PREFIX=$2; shift 2 ;;
        --gcc-lib-prefix) GCC_LIB_PREFIX=$2; shift 2 ;;
        --prefix) INSTALL_PREFIX=$2; shift 2 ;;
        --llvm-prefix) LLVM_INSTALL_PREFIX=$2; shift 2 ;;
        --llvm-version) LLVM_VERSION=$2; shift 2 ;;
        --with-lldb) WITH_LLDB=1; shift 1 ;;
        --build-dir) BUILD_DIR=$2; shift 2 ;;
        --help) usage; exit 0 ;;
        --) shift; break ;;
        *) echo "Incorrect argument given -> $1"; usage; exit 255 ;;
    esac
done

if [ -z "$BUILD_DIR" ]; then
    # TODO(cschwarzgruber): Create temporary directory for building.
    echo "You need to implement this :-)"
    usage; exit 1
fi

if [ -z "$INSTALL_PREFIX" ]; then
    echo "You need to provide the install prefix path: --prefix"
    usage; exit 1
fi

if [ -z "$BUILD_LIST" ]; then
    echo -n "Don't know what to build, please provide a semicolon seperated "
    echo "list of software packages to build."
    usage; exit 1
fi

################# COMPILER's START
# Put compilers into a seperate path. It's easier to uninstall (remove) it later.
# GCC doesn't provide an uninstall target, for example.
# Use two seperate variables for GCC to use icecc e.g. to distribute the jobs
# among multiple machines.
################# COMPILER's END

function compile_install_gdb()
{
  local GDB_VERSION=7.10.1
  local GDB_TAR=gdb-$GDB_VERSION.tar.gz


  test ! -d gdb-$GDB_VERSION &&
      test ! -f $GDB_TAR &&
      wget http://ftp.gnu.org/gnu/gdb/gdb-$GDB_VERSION/$GDB_TAR

  test ! -d gdb-$GDB_VERSION &&
      tar xf $GDB_TAR

  cd gdb-$GDB_VERSION
  test -d build &&
      rm -rf build
  mkdir -p build
  cd build
  ../configure --prefix=$GDB_INSTALL_PREFIX \
               --target=arm-buildroot-linux-uclibcgnueabi
  $MAKE
  $MAKE install

  cd ../gdb/gdbserver
  test -d build && rm -rf build
  mkdir -p build
  cd build
  ../configure --prefix=$GDB_INSTALL_PREFIX \
               --host=arm-buildroot-linux-uclibcgnueabi
  eval $MAKE_BUILD
  eval $MAKE_INSTALL
}

# Requires:
#  - gmp-devel
#  - mpfr-devel
#  - libmpc-devel
#  - some 32-bit libraries like glibc-devel
# TODO(cschwarzgruber): Add some code to also compile mentioned packages above
# from scratch.
function compile_install_gcc()
{
  local GCC_VERSION=5.2.0
  local GCC_TAR=gcc-$GCC_VERSION.tar.bz2

  test ! -d gcc-$GCC_VERSION &&
      test ! -f $GCC_TAR &&
      wget http://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/$GCC_TAR

  test ! -d gcc-$GCC_VERSION &&
      tar xf $GCC_TAR

  cd gcc-$GCC_VERSION
  mkdir -p build
  cd build
  ../configure \
      --prefix=$GCC_PREFIX \
      --with-system-zlib \
      --without-included-gettext \
      --enable-threads=posix \
      --enable-nls \
      --enable-objc-gc \
      --enable-clocale=gnu \
      --enable-plugin \
      --enable-multilib \
      --enable-checking=release \
      --enable-__cxa_atexit \
      --enable-gnu-unique-object \
      --disable-libunwind-exceptions \
      --enable-linker-build-id \
      --with-linker-hash-style=gnu \
      --enable-initfini-array \
      --disable-libgcj \
      --enable-bootstrap \
      --with-isl \
      --enable-libmpx \
      --enable-gnu-indirect-function \
      --with-arch_32=i686 \
      --with-tune=generic \
      --build=x86_64-redhat-linux \
      --host=x86_64-redhat-linux \
      --enable-languages=c,c++,objc
  eval $MAKE_BUILD
  eval $MAKE_INSTALL
}

function compile_install_llvm_clang()
{
  local COMPRESSION
  if echo "$LLVM_VERSION" "3.5" | awk '{exit $1<$2?0:1}'; then
      COMPRESSION=gz
  else
      COMPRESSION=xz
  fi
  readonly LLVM_TAR=llvm-$LLVM_VERSION.src.tar.$COMPRESSION
  readonly CFE_TAR=cfe-$LLVM_VERSION.src.tar.$COMPRESSION
  readonly COMPILER_RT_TAR=compiler-rt-$LLVM_VERSION.src.tar.$COMPRESSION
  readonly LLVM_DIR=llvm-$LLVM_VERSION

  # llvm src
  test ! -d $LLVM_DIR &&
      test ! -f $LLVM_TAR  &&
      wget http://llvm.org/releases/$LLVM_VERSION/$LLVM_TAR
  test ! -d $LLVM_DIR &&
      tar xf $LLVM_TAR &&
      mv llvm-$LLVM_VERSION.src $LLVM_DIR

  # clang src
  test ! -d $LLVM_DIR/tools/clang &&
      test ! -f $CFE_TAR &&
      wget http://llvm.org/releases/$LLVM_VERSION/$CFE_TAR
  test ! -d $LLVM_DIR/tools/clang &&
      tar xf $CFE_TAR -C $LLVM_DIR/tools &&
      mv $LLVM_DIR/tools/cfe-$LLVM_VERSION.src $LLVM_DIR/tools/clang

  # compiler-rt src
  test ! -d $LLVM_DIR/projects/compiler-rt &&
      test ! -f $COMPILER_RT_TAR &&
      wget http://llvm.org/releases/$LLVM_VERSION/$COMPILER_RT_TAR
  test ! -d $LLVM_DIR/projects/compiler-rt &&
      tar xf $COMPILER_RT_TAR -C $LLVM_DIR/projects &&
      mv $LLVM_DIR/projects/compiler-rt-$LLVM_VERSION.src \
         $LLVM_DIR/projects/compiler-rt

  if [ ! -z "$WITH_LLDB" ]; then
      readonly COMPILER_LLDB_TAR=lldb-$LLVM_VERSION.src.tar.$COMPRESSION
      test ! -d $LLVM_DIR/tools/lldb &&
          test ! -f $COMPILER_LLDB_TAR &&
          wget http://llvm.org/releases/$LLVM_VERSION/$COMPILER_LLDB_TAR
      test ! -d $LLVM_DIR/tools/lldb &&
          tar xf $COMPILER_LLDB_TAR -C $LLVM_DIR/tools &&
          mv $LLVM_DIR/tools/lldb-$LLVM_VERSION.src \
             $LLVM_DIR/tools/lldb
  fi
  # TODO(cschwarzgruber): Maybe add the other available LLVM/Clang software
  # packages too, but make them optional.

  mkdir -p $LLVM_DIR/build
  cd $LLVM_DIR/build

  test -z "$LLVM_INSTALL_PREFIX" && LLVM_INSTALL_PREFIX=$INSTALL_PREFIX

  # http://llvm.org/releases/3.8.0/docs/CMake.html
  $CMAKE ../ -G "$CGTOOL"                                                     \
        -DCMAKE_CXX_COMPILER="$GCC_PREFIX/bin/g++"                            \
        -DCMAKE_C_COMPILER="$GCC_PREFIX/bin/gcc"                              \
        -DCMAKE_BUILD_TYPE=Release                                            \
        -DCMAKE_INSTALL_PREFIX="$LLVM_INSTALL_PREFIX"                         \
        -DLLVM_LIBDIR_SUFFIX=64                                               \
        -DLLVM_TARGETS_TO_BUILD="X86;ARM;CppBackend"                          \
        -DLLVM_BUILD_EXAMPLES=OFF                                             \
        -DLLVM_INCLUDE_EXAMPLES=OFF                                           \
        -DLLVM_INCLUDE_TESTS=OFF                                              \
        -DLLVM_APPEND_VC_REV=OFF                                              \
        -DLLVM_ENABLE_CXX1Y=ON                                                \
        -DLLVM_ENABLE_ASSERTIONS=OFF                                          \
        -DLLVM_ENABLE_EH=ON                                                   \
        -DLLVM_ENABLE_PIC=ON                                                  \
        -DLLVM_ENABLE_RTTI=ON                                                 \
        -DLLVM_ENABLE_WARNINGS=ON                                             \
        -DLLVM_TARGET_ARCH="host"                                             \
        -DLLVM_ENABLE_FFI=ON                                                  \
        -DLLVM_ENABLE_ZLIB=ON                                                 \
        -DLLVM_USE_OPROFILE=ON                                                \
        -DLLVM_PARALLEL_COMPILE_JOBS="$CORES"                                 \
        -DLLVM_PARALLEL_LINK_JOBS="1"                                         \
        -DLLVM_BUILD_LLVM_DYLIB=ON                                            \
        -DLLVM_LINK_LLVM_DYLIB=ON

  eval $CMAKE_BUILD
  eval $CMAKE_INSTALL_RELEASE
  ### Those are default values
  # -DDEFAULT_SYSROOT=""
  # -DLLVM_BUILD_32_BITS_=OFF
  # -DLLVM_BUILD_DOCS=OFF
  # -DLLVM_ENABLE_DOXYGEN=OFF
  # -DLLVM_ENABLE_DOXYGEN_QT_HELP=OFF
  # -DLLVM_DOXYGEN_SVG=OFF
  # -DLLVM_ENABLE_SPHINX=OFF
  # -DSPHINX_OUTPUT_HTML=ON
  # -DSPHINX_OUTPUT_MAN=ON
  # -DSPHINX_WARNINGS_AS_ERRORS=ON
  # -DBUILD_SHARED_LIBS=ON
  ### Only useful on OS X
  # -DLLVM_CREATE_XCODE_TOOLCHAIN=OFF
}

function compile_install_rtags()
{
  if [ ! -d $BUILD_DIR/rtags ]; then
	  $GIT clone --recursive https://github.com/Andersbakken/rtags.git
	  cd $BUILD_DIR/rtags
  else
	  cd $BUILD_DIR/rtags
	  $GIT pull
          $GIT submodule init
	  $GIT submodule update
  fi

  mkdir -p build
  cd build
  cmake ../ -G "$CGTOOL" \
	-DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
	-DCMAKE_C_COMPILER=$GCC_PREFIX/bin/gcc \
	-DCMAKE_CXX_COMPILER=$GCC_PREFIX/bin/g++ \
	-DLIBCLANG_LLVM_CONFIG_EXECUTABLE=$LLVM_INSTALL_PREFIX/bin/llvm-config \
	-DCMAKE_CXX_LINK_FLAGS="-Wl,-rpath,$GCC_LIB_PREFIX/lib64 -Wl,-rpath,$GCC_LIB_PREFIX/lib -Wl,-rpath,$LLVM_INSTALL_PREFIX/lib64 -Wl,-rpath,$LLVM_INSTALL_PREFIX/lib" \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  eval $CMAKE_BUILD
  eval $CMAKE_INSTALL
}


for pkg in ${BUILD_LIST/;/ }; do
  # TODO(cschwarzgruber): Build into temporary directory if --build-dir was not specified.
  if [ -z "$BUILD_DIR" ]; then
      BUILD_DIR=/home/cschwarzgruber/Temp/bdir
  fi
  test -d $BUILD_DIR || mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  compile_install_$pkg
done

exit 0
