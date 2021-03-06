#!/bin/bash

BOOTNODE_FLAGS="--bootnodes enode://0478aa13c91aa0db8e93b668313b7eb0532fbdb24f64772375373b14dbe326c238ad09ab4469f6442c9a9753f1275aeec2e531912c14a958ed1feb4ae7e227ef@127.0.0.1:30301"
GENESIS="genesis.json"

GDEX="../build/bin/gdex"
BOOTNODE="../build/bin/bootnode"


CONTINUE=false
SMOKETEST=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --continue)
    CONTINUE=true
    ;;
    --smoke-test)
    SMOKETEST=true
    ;;
  esac
  shift
done


if [ ! -e "$BOOTNODE" ]; then
  echo "Building bootnode for the first time ..."
  go build -o $BOOTNODE ../cmd/bootnode
fi

# Start bootnode.
$BOOTNODE -nodekey keystore/bootnode.key --verbosity=9 > bootnode.log 2>&1 &

# Kill all previous instances.
pkill -9 -f gdex

logsdir=$PWD/log-$(date '+%Y-%m-%d-%H:%M:%S')
mkdir $logsdir

if [ -e log-latest ]; then
  rm -f log-previous
  mv log-latest log-previous
fi

rm -f log-latest
ln -s $logsdir log-latest


# the recovery contract address 0x80859F3d0D781c2c4126962cab0c977b37820e78 is deployed using keystore/monkey.key
if $SMOKETEST; then
  if [ `uname` == "Darwin" ]; then
    sed -i '' 's/"contract":.*,/"contract": "0x80859F3d0D781c2c4126962cab0c977b37820e78",/g' genesis.json
  else
    sed -i 's/"contract":.*,/"contract": "0x80859F3d0D781c2c4126962cab0c977b37820e78",/g' genesis.json
  fi
fi


python << __FILE__
import re
import time

with open('$GENESIS', 'r') as f:
  data = f.read()

with open('$GENESIS', 'w') as f:
  dMoment = int(time.time()) + 15
  f.write(re.sub('"dMoment": [0-9]+,', '"dMoment": %d,' % dMoment, data))
__FILE__

# A standalone RPC server for accepting RPC requests.
datadir=$PWD/Dexon.rpc
if ! $CONTINUE; then
  rm -rf $datadir
  $GDEX --datadir=$datadir init ${GENESIS}
fi
$GDEX \
  ${BOOTNODE_FLAGS} \
  --verbosity=3 \
  --gcmode=archive \
  --datadir=$datadir --nodekey=keystore/rpc.key \
  --rpc --rpcapi=eth,net,web3,debug \
  --rpcaddr=0.0.0.0 --rpcport=8545 \
  --ws --wsapi=eth,net,web3,debug \
  --wsaddr=0.0.0.0 --wsport=8546  \
  --wsorigins='*' --rpcvhosts='*' --rpccorsdomain="*" \
  > $logsdir/gdex.rpc.log 2>&1 &

NUM_NODES=$(cat ${GENESIS} | grep 'DEXON Test Node' | wc -l)

RECOVERY_FLAGS="--recovery.network-rpc=https://rinkeby.infura.io"

if $SMOKETEST; then
  RECOVERY_FLAGS="--recovery.network-rpc=http://127.0.0.1:8645"
fi


# Nodes
for i in $(seq 0 $(($NUM_NODES - 1))); do
  datadir=$PWD/Dexon.$i

  if ! $CONTINUE; then
    rm -rf $datadir
    $GDEX --datadir=$datadir init ${GENESIS}
  fi
  $GDEX \
    ${BOOTNODE_FLAGS} \
    --bp \
    --verbosity=4 \
    --gcmode=archive \
    --datadir=$datadir --nodekey=keystore/test$i.key \
    --port=$((30305 + $i)) \
    ${RECOVERY_FLAGS} \
    --rpc --rpcapi=eth,net,web3,debug \
    --rpcaddr=0.0.0.0 --rpcport=$((8547 + $i * 2)) \
    --ws --wsapi=eth,net,web3,debug \
    --wsaddr=0.0.0.0 --wsport=$((8548 + $i * 2)) \
    --wsorigins='*' --rpcvhosts='*' --rpccorsdomain="*" \
    --pprof --pprofaddr=localhost --pprofport=$((6060 + $i)) \
    > $logsdir/gdex.$i.log 2>&1 &
done

if ! $SMOKETEST; then
  tail -f $logsdir/gdex.*.log
fi
