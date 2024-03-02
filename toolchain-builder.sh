#! /bin/bash
# inspired by https://stackoverflow.com/questions/42022659/how-to-get-a-smaller-toolchain-from-scratch
set -euo pipefail

export TGT_FLAGS="--with-float=hard --with-fpu=vfp"
export OWRT_TARGET="bcm27xx"
export OWRT_SUBTARGET="bcm2708"
export OWRT_PAIR="${OWRT_TARGET}/${OWRT_SUBTARGET}"
# export ARCH="armv6kz+fp"
export ARCH="arm"
export CPU="arm1176jzf-s"
# export CPU_EXT="vfp"
# export CPU=arm
export CLIB=musleabihf
# export TARGET_TRIPLET=${CPU}-linux-${CLIB}
export TARGET_TRIPLET=${ARCH}-linux-${CLIB}
export CROSS_PREFIX="${PWD}/output/cross"
export NATIVE_PREFIX="${PWD}/output/native"
export SOURCE_DIR="${PWD}/sources"
export BUILD_DIR="${PWD}/working"
export PATH=${CROSS_PREFIX}/bin:$PATH 

mkdir ${SOURCE_DIR} -p ; cd ${SOURCE_DIR}

# doing this with spinning metal platters = bad idea 😅

wget -N https://ftpmirror.gnu.org/binutils/binutils-2.42.tar.gz &
wget -N https://ftpmirror.gnu.org/gcc/gcc-13.2.0/gcc-13.2.0.tar.gz &
# wget https://www.kernel.org/pub/linux/kernel/v3.x/linux-3.12.6.tar.bz2
wget -N https://www.musl-libc.org/releases/musl-latest.tar.gz &
wget -N https://ftpmirror.gnu.org/mpfr/mpfr-4.2.1.tar.gz &
wget -N https://ftpmirror.gnu.org/gmp/gmp-6.3.0.tar.gz &
wget -N https://ftpmirror.gnu.org/mpc/mpc-1.3.1.tar.gz &

wait -f
# **** Get Raspberry Pi headers ****
(
   [[ -d raspberry-kernel ]] || git clone https://github.com/raspberrypi/linux raspberry-kernel
    cd raspberry-kernel
    git fetch
    # KERNEL=kernel make ARCH=arm CROSS_COMPILE=${TARGET_TRIPLET}- INSTALL_HDR_PATH=${CROSS_PREFIX}/${TARGET_TRIPLET}  bcmrpi_defconfig
    KERNEL=kernel make ARCH=${ARCH} CROSS_COMPILE=${TARGET_TRIPLET}- INSTALL_HDR_PATH=${CROSS_PREFIX}/${TARGET_TRIPLET}  headers_install
    echo -e "\n\nTarget headers installed\n\n"
    cd ..
) &
# **********************************

(cat *.tar.gz | tar -xvzvf - -i --keep-newer-files) &
wait -f

# **** GNU binutils (native) ****
mkdir ${BUILD_DIR}/binutils -p ; cd ${BUILD_DIR}/binutils
echo -e "\n\nMoved into $PWD\n\n"
${SOURCE_DIR}/binutils-*/configure --prefix=${NATIVE_PREFIX} --disable-nls --enable-werror=no --disable-multilib

# TODO: Make this a function?
if (make -j$(nproc) -Orecurse); then
    echo -e "\n\nmake binutils (native) finished (first try!)\n\n"
elif (read -p "'make binutils' (native) problem with first attempt" ; make -j1 -d); then
    echo -e "\n\nmake binutils (native) finished (second try)\n\n"
else
    echo "'make binutils' (native) Failure!"
    exit 2
fi
make install || make -d install || (echo "'make install' failed (binutils native)" ; exit 2 )
# *******************************

# **** GNU Compilier Collection (native) ****
cd ${SOURCE_DIR}/gcc-*/
[[ -h mpfr ]] || ln -s ../mpfr-*/ mpfr
[[ -h gmp  ]] || ln -s ../gmp-*/ gmp
[[ -h mpc  ]] || ln -s ../mpc-*/ mpc

mkdir ${BUILD_DIR}/gcc -p ; cd ${BUILD_DIR}/gcc
${SOURCE_DIR}/gcc-*/configure --prefix=${NATIVE_PREFIX} --disable-nls --enable-languages=c --disable-multilib
echo -e "\n\nFinished configuring gcc\n\nBuilding gcc…"

(
  Colors=(
    '064;000;000' '128;000;000' '192;000;000' '255;000;000'
    '255;064;000' '255;128;000' '255;192;000' '255;255;000'
    '192;255;000' '128;255;000' '064;255;000' '000;255;000'
    '000;255;064' '000;255;128' '000;255;192' '000;255;255'
    '000;192;255' '000;128;255' '000;064;255' '000;000;255'
    '000;000;192' '000;000;128' '000;000;064' '000;000;000'
  )
  while true; do
    for i in ${Colors[@]}; do
      echo -n $'\x1B[38;2;'${i}'m'
      for j in {1..4}; do
        echo -n ". "$'\x08'
        nice -n 19 nice -n 19 sleep 5
      done
    done
    echo -n $'\x0D\x1B[0m'
    for i in ${Colors[@]}; do
      echo -n $'\x1B[38;2;'${i}'m'
      for j in {1..4}; do
        echo -n "* "$'\x08'
        nice -n 19 nice -n 19 sleep 5
      done
    done
    echo -n $'\x0D\x1B[0m'
  done
) &

if (make -j$(nproc) -Orecurse); then
  kill $!
  echo -e $'\x0D\x1B[0m\x07' "\n\nFinished building native gcc(first try!)\n\n"
elif (read -p '\x07' "'make gcc' (native) problem with first attempt" ; make -j1 -d V=sc); then
  kill $!
  echo -e "\x07\n\nFinished building native gcc (second try)\n\n"
else
  kill $!
  echo "'make gcc' (native) Failure!"
  exit 2
fi
make install || make -d install || (echo "'make install' failed (gcc native)"; exit 2)
# *******************************************
# done with host system

# **** GNU binutils (cross) ****
mkdir ${BUILD_DIR}/${CPU}-binutils -p ; cd ${BUILD_DIR}/${CPU}-binutils
echo "Moved into $PWD"

${SOURCE_DIR}/binutils-*/configure --target=${TARGET_TRIPLET} --prefix=${CROSS_PREFIX} --with-sysroot --disable-nls --disable-werror --disable-multilib
if (make -j$(nproc) -Orecurse); then
  echo -e "\n\nmake binutils (cross) finished (first try!)\n\n"
elif (read -p "'make binutils' (cross) problem with first attempt" ; make -j1 -d V=sc); then
  echo -e "\n\nmake binutils (cross) finished (second try)\n\n"
else
  echo "'make binutils' (cross) Failure!"
  exit 2
fi
make install
# should install to prefix/target/bin
# ******************************

# **** GNU Compilier Collection (cross) ****
mkdir ${BUILD_DIR}/bootstrap-${CPU}-gcc -p ; cd ${BUILD_DIR}/bootstrap-${CPU}-gcc
${SOURCE_DIR}/gcc-*/configure --target=${TARGET_TRIPLET} --prefix=${CROSS_PREFIX} --disable-nls --enable-languages=c --disable-multilib --disable-threads --disable-shared --with-float=soft --with-cpu=${CPU}

make all-gcc install-gcc
make all-target-libgcc install-target-libgcc

mkdir ${BUILD_DIR}/musl -p
cd ${BUILD_DIR}/musl
# CC=${CROSS_PREFIX}/bin/${TARGET_TRIPLET}-gcc CFLAGS=-Wa,-mfloat-abi=hard ${SOURCE_DIR}/musl-*/configure  --prefix=${CROSS_PREFIX}/${TARGET_TRIPLET} --enable-optimize CROSS_COMPILE=${TARGET_TRIPLET}-
CC=${TARGET_TRIPLET}-gcc CFLAGS=-Wa,-mfloat-abi=hard ${SOURCE_DIR}/musl-*/configure --prefix=${CROSS_PREFIX}/${TARGET_TRIPLET}/ --enable-optimize CROSS_COMPILE=${TARGET_TRIPLET}-
make
make install

mkdir ${BUILD_DIR}/${CPU}-gcc -p
cd ${BUILD_DIR}/${CPU}-gcc
${SOURCE_DIR}/gcc-*/configure --target=${TARGET_TRIPLET} --prefix=${CROSS_PREFIX} --disable-nls --enable-languages=c,c++ --disable-multilib --enable-threads --enable-shared --with-float=soft --with-cpu=${CPU} --enable-target-optspace --disable-libgomp --disable-libmudflap --without-isl --without-cloog --disable-decimal-float --disable-libssp --disable-libsanitizer --enable-lto --with-host-libstdcxx=-lstdc++

make
make install-strip