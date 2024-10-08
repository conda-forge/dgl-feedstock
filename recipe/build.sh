#!/bin/bash
set -euxo pipefail

rm -rf build || true

if [ ${cuda_compiler_version} != "None" ]; then
  USE_CUDA=ON
  # Remove -std=c++17 from CXXFLAGS for compatibility with nvcc
  CXXFLAGS="$(echo $CXXFLAGS | sed -e 's/ -std=[^ ]*//')"
  export NJOBS=""  # disable parallel jobs to avoid OOM
  if [[ ${cuda_compiler_version} == 9.0* ]]; then
      export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;7.0+PTX"
      export CUDAARCHS="35;50;60;70"
  elif [[ ${cuda_compiler_version} == 9.2* ]]; then
      export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0+PTX"
      export CUDAARCHS="35;50;60;61;70"
  elif [[ ${cuda_compiler_version} == 10.* ]]; then
      export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5+PTX"
      export CUDAARCHS="35;50;60;61;70;75"
  elif [[ ${cuda_compiler_version} == 11.0* ]]; then
      export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0+PTX"
      export CUDAARCHS="35;50;60;61;70;75;80"
  elif [[ ${cuda_compiler_version} == 11.1 ]]; then
      export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX"
      export CUDAARCHS="35;50;60;61;70;75;80;86"
  elif [[ ${cuda_compiler_version} == 11.2 ]]; then
      export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX"
      export CUDAARCHS="35;50;60;61;70;75;80;86"
  elif [[ ${cuda_compiler_version} == 11.8 ]]; then
      # We removed 3.5 from the list (deprecated, build times out)
      export TORCH_CUDA_ARCH_LIST="5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9+PTX"
      export CUDAARCHS="50;60;61;70;75;80;86;89"
  elif [[ ${cuda_compiler_version} == 12.0 ]]; then
      export TORCH_CUDA_ARCH_LIST="5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0+PTX"
      export CUDAARCHS="50;60;61;70;75;80;86;89;90"
  else
      echo "unsupported cuda version. edit build.sh"
      exit 1
  fi
  CUDA_CMAKE_OPTIONS="-DCUDA_ARCH_NAME=Manual"
  CUDA_CMAKE_OPTIONS+=" -DCUDA_ARCH_BIN=${CUDAARCHS}"
  CUDA_CMAKE_OPTIONS+=" -DCUDA_ARCH_PTX=${CUDAARCHS}"

  # Add NVVM's `bin` directory to the `$PATH`.
  # This should fix an error finding `cicc`.
  # ref: https://forums.developer.nvidia.com/t/when-i-arch-option-error-sh-cicc-command-not-found-takes-place/31753/2
  # xref: https://github.com/conda-forge/cuda-nvcc-impl-feedstock/issues/9
  if [[ "${cuda_compiler_version}" == 12* ]]; then
    export PATH="${PATH}:${BUILD_PREFIX}/nvvm/bin"
    # Add more precedence to thrust, cub, libcudacxx include directories;
    # otherwise, cuda-cccl's get used, which are older and incompatible with dgl usage.
    CUDA_CMAKE_OPTIONS+=" -DCUDA_NVCC_FLAGS=-Xcompiler=-I${SRC_DIR}/third_party/cccl/thrust,-I${SRC_DIR}/third_party/cccl/cub,-I${SRC_DIR}/third_party/cccl/libcudacxx/include"
  fi
else
  CUDA_CMAKE_OPTIONS=""
  USE_CUDA=OFF
  CFLAGS="${CFLAGS} -std=c17"
  CXXFLAGS="${CXXFLAGS} -std=c++17"
  export NJOBS="-j$(nproc || sysctl -n hw.logicalcpu)"
fi

# SEE PR #5 (can't build to do aligned_alloc missing on osx)
if [[ $(uname) == "Darwin" ]]; then
	USE_LIBXSMM=OFF
    USE_LIBURING=OFF
	# https://conda-forge.org/docs/maintainer/knowledge_base.html#newer-c-features-with-old-sdk
	# error: 'shared_mutex' is unavailable: introduced in macOS 10.1
	CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
elif [[ $(uname) == "Linux" ]]; then
    USE_LIBXSMM=ON
    USE_LIBURING=ON
else
	USE_LIBXSMM=ON
    USE_LIBURING=OFF
fi

CMAKE_FLAGS="${CMAKE_ARGS} -DCMAKE_INSTALL_PREFIX=${PREFIX} -DCMAKE_BUILD_TYPE=Release"
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
  -DUSE_LIBURING=${USE_LIBURING} \
  -DUSE_OPENMP=ON \
  -DBUILD_TYPE=release \
  ${CMAKE_FLAGS} \
  ${CUDA_CMAKE_OPTIONS} \
  ${SRC_DIR}

make ${NJOBS} VERBOSE=1
cd ../python
${PYTHON} -m pip install . --no-deps -vv
