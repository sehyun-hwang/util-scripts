echo $1
docker run --rm -it \
  -w /root -v $PWD:/root \
  -u $(id -u):$(id -g) \
  emscripten/emsdk \
  emcc -o $1.js $1 -O3 -s WASM=1 -s MODULARIZE=1 -s EXPORT_ES6=1 -s "EXTRA_EXPORTED_RUNTIME_METHODS=['ccall']"
