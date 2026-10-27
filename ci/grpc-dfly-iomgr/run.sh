#!/bin/sh
# grpc#43396: iomgr の dual-stack を DragonFly で測る。
# PR の枝 (BEFORE) と、その上に iomgr の直しを載せた物 (AFTER) を同じ木で
# 順に建て、helloworld を EventEngine (既定) と iomgr の両方で通す。
set -u
BEFORE=d797c218374001e41d999416edbe687e4127f22a
AFTER=74533b2a0ce6a4abfe54c42a749a225adbb1d4d1
W=/var/tmp/g; mkdir -p $W; cd $W
uname -a
git clone -q https://github.com/zakinko/grpc src
cd src
git fetch -q origin dragonfly-iomgr-test
git checkout -q $BEFORE
git submodule update -q --init --depth 1 || exit 1

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
