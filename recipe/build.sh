#!/bin/bash
set -euxo pipefail

rm -rf build || true


if [ ${cuda_compiler_version} != "None" ]; then
  CUDA_CMAKE_OPTIONS="-DCUDA_ARCH_NAME=All"
  USE_CUDA=ON
  # Remove -std=c++17 from CXXFLAGS for compatibility with nvcc
  CXXFLAGS="$(echo $CXXFLAGS | sed -e 's/ -std=[^ ]*//')"
else
  CUDA_CMAKE_OPTIONS=""
  USE_CUDA=OFF
  CFLAGS="${CFLAGS} -std=c17"
  CXXFLAGS="${CXXFLAGS} -std=c++17"
fi

# SEE PR #5 (can't build to do aligned_alloc missing on osx)
if [[ $(uname) == "Darwin" ]]; then
	USE_LIBXSMM=OFF
	# https://conda-forge.org/docs/maintainer/knowledge_base.html#newer-c-features-with-old-sdk
	# error: 'shared_mutex' is unavailable: introduced in macOS 10.1
	CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
else
	USE_LIBXSMM=ON
fi

CMAKE_FLAGS="${CMAKE_ARGS} -DCMAKE_INSTALL_PREFIX=${PREFIX} -DCMAKE_BUILD_TYPE=Release -DPython_EXECUTABLE=${PYTHON}"
if [[ ${cuda_compiler_version} != "None" ]]; then
    if [[ ${cuda_compiler_version} == 9.0* ]]; then
        export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;7.0+PTX"
    elif [[ ${cuda_compiler_version} == 9.2* ]]; then
        export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0+PTX"
    elif [[ ${cuda_compiler_version} == 10.* ]]; then
        export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5+PTX"
    elif [[ ${cuda_compiler_version} == 11.0* ]]; then
        export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0+PTX"
    elif [[ ${cuda_compiler_version} == 11.1 ]]; then
        export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX"
    elif [[ ${cuda_compiler_version} == 11.2 ]]; then
        export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX"
    elif [[ ${cuda_compiler_version} == 11.8 ]]; then
        export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9+PTX"
    elif [[ ${cuda_compiler_version} == 12.0 ]]; then
        export TORCH_CUDA_ARCH_LIST="5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0+PTX"
    else
        echo "unsupported cuda version. edit build.sh"
        exit 1
    fi
fi
echo $CONDA_PREFIX

mkdir build
cd build

cmake -DUSE_CUDA=${USE_CUDA} \
  -DUSE_CONDA_INCLUDES=ON \
  -DEXTERNAL_DLPACK_PATH=${BUILD_PREFIX}/include \
  -DEXTERNAL_DMLC_PATH=${BUILD_PREFIX}/include \
  -DEXTERNAL_DMLC_LIB_PATH=${BUILD_PREFIX}/lib \
  -DEXTERNAL_PHMAP_PATH=${BUILD_PREFIX}/include \
  -DEXTERNAL_NANOFLANN_PATH=${BUILD_PREFIX}/include \
  -DEXTERNAL_METIS_PATH=${BUILD_PREFIX}/include \
  -DEXTERNAL_METIS_LIB_PATH=${BUILD_PREFIX}/lib \
  -DUSE_LIBXSMM=${USE_LIBXSMM} \
  -DUSE_OPENMP=ON \
  ${CMAKE_FLAGS} \
  ${CUDA_CMAKE_OPTIONS} \
  ${SRC_DIR}

make -j$(nproc)
cd ../python
${PYTHON} setup.py install --single-version-externally-managed --record=record.txt
