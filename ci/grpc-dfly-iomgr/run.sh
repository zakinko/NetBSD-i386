#!/bin/sh
# grpc#43396: iomgr の dual-stack を DragonFly で測る。
# PR の枝 (BEFORE) と、その上に iomgr の直しを載せた物 (AFTER) を同じ木で
# 順に建て、helloworld を EventEngine (既定) と iomgr の両方で通す。
set -u
BEFORE=d797c218374001e41d999416edbe687e4127f22a
AFTER=74533b2a0ce6a4abfe54c42a749a225adbb1d4d1
export CC=clang19 CXX=clang++19
W=/var/tmp/g; mkdir -p $W; cd $W
uname -a; $CXX --version | head -1
git clone -q https://github.com/zakinko/grpc src
cd src
git fetch -q origin dragonfly-iomgr-test
git checkout -q $BEFORE
git submodule update -q --init --depth 1 || exit 1

# 測定のためだけの手当て。直す前と後の両方に同じく効く (AFTER との差は
# dualstack_socket_posix.cc だけで、ここで触る file と重ならない)。
# 1) master の latent_see.cc は素の abs(int64_t) を書き、DragonFly の libstdc++
#    では int abs(int) しか見えず std::min が型で落ちる。
sed -i '' 's/std::min(earliest_timestamp, abs(/std::min(earliest_timestamp, std::abs(/' \
  src/core/util/latent_see.cc
grep -q 'std::abs(event.timestamp_end)' src/core/util/latent_see.cc || exit 1
# 2) 同梱の abseil に DragonFly の腕が無い (abseil#2160 の build に効く部分)。
git -C third_party/abseil-cpp apply -v \
  --include='absl/base/config.h' --include='absl/base/internal/sysinfo.cc' \
  --include='absl/debugging/internal/vdso_support.cc' \
  "$GITHUB_WORKSPACE/ci/grpc-dfly-iomgr/abseil-2160.diff" || exit 1
# 同梱の版は ABSL_HAVE_MMAP を OS の並びで決め、DragonFly が無い (master は
# __has_include(<sys/mman.h>))。無いと poison.cc が宣言の無い data を読んで
# 落ちるので、その直し (abseil#1914, a9268d5f) も当てる。
f=third_party/abseil-cpp/absl/base/config.h
sed -i '' 's/defined(__OpenBSD__) || defined(__NetBSD__) || defined(__QNX__) ||/defined(__OpenBSD__) || defined(__NetBSD__) || defined(__QNX__) || defined(__DragonFly__) ||/' $f
grep -q '__QNX__) || defined(__DragonFly__)' $f || exit 1
git -C third_party/abseil-cpp apply -v \
  "$GITHUB_WORKSPACE/ci/grpc-dfly-iomgr/abseil-1914.diff" || exit 1
# 同梱の版は raw_logging.cc の条件の並びも違うので sed で。
f=third_party/abseil-cpp/absl/base/internal/raw_logging.cc
sed -i '' 's/defined(__native_client__) || defined(__OpenBSD__) ||/defined(__native_client__) || defined(__OpenBSD__) || defined(__DragonFly__) ||/' $f
grep -q 'defined(__DragonFly__)' $f || exit 1
# 同梱の版は time_zone_format.cc の行の形が #2160 の土台と違うので sed で。
f=third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc
sed -i '' 's/!defined(__FreeBSD__) \&\& !defined(__OpenBSD__)$/!defined(__FreeBSD__) \&\& !defined(__OpenBSD__) \&\& !defined(__DragonFly__)/' $f
grep -q '!defined(__DragonFly__)' $f || exit 1

build() {
  cmake -S . -B $W/b -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DgRPC_SSL_PROVIDER=module \
    -DgRPC_BUILD_CSHARP_EXT=OFF -DCMAKE_INSTALL_PREFIX=$W/inst >$W/cmake.log 2>&1 \
    || { tail -40 $W/cmake.log; exit 1; }
  ninja -C $W/b install >$W/ninja.log 2>&1 || { tail -60 $W/ninja.log; exit 1; }
  rm -rf $W/ex
  cmake -S examples/cpp/helloworld -B $W/ex -G Ninja -DCMAKE_PREFIX_PATH=$W/inst \
    >$W/ex.log 2>&1 && ninja -C $W/ex greeter_client greeter_server >>$W/ex.log 2>&1 \
    || { tail -40 $W/ex.log; exit 1; }
}

probe() {  # $1 label, $2 GRPC_EXPERIMENTS
  GRPC_EXPERIMENTS="$2" $W/ex/greeter_server --port=50051 >$W/srv.log 2>&1 &
  s=$!; sleep 3
  GRPC_EXPERIMENTS="$2" timeout 20 $W/ex/greeter_client \
    --target=127.0.0.1:50051 >$W/cli.log 2>&1
  rc=$?
  kill $s; wait $s 2>/dev/null
  echo "RESULT $1 exp='$2' rc=$rc: $(tr '\n' ' ' <$W/cli.log | cut -c1-300)"
  echo "  server: $(tr '\n' ' ' <$W/srv.log | cut -c1-300)"
}

IOMGR=-event_engine_client,-event_engine_listener
build
probe before ""
probe before "$IOMGR"
git checkout -q $AFTER
build
probe after ""
probe after "$IOMGR"
