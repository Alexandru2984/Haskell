#!/bin/bash
cabal build -O2
cp dist-newstyle/build/x86_64-linux/ghc-*/haskell-api-monitor-*/x/api-contract-monitor/build/api-contract-monitor/api-contract-monitor ./dist/
