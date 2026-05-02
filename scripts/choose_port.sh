#!/bin/bash
# Find an available port starting from 3060
PORT=3060
while netstat -an | grep -q ":$PORT "; do
  PORT=$((PORT + 1))
done
echo "Found available port: $PORT"
sed -i "s/^APP_PORT=.*/APP_PORT=$PORT/" /home/micu/haskell/.env
echo $PORT
