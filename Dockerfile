FROM ubuntu:16.04
MAINTAINER Waleed Abdulla <waleed.abdulla@gmail.com>

RUN apt-get update

# Supress warnings about missing front-end. As recommended at:
# http://stackoverflow.com/questions/22466255/is-it-possibe-to-answer-dialog-questions-when-installing-under-docker
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y --no-install-recommends apt-utils

# Developer Essentials
RUN apt-get install -y --no-install-recommends git curl vim

# Build tools
RUN apt-get install -y --no-install-recommends build-essential cmake

# OpenBLAS
RUN apt-get install -y --no-install-recommends libopenblas-dev

#
# Python 3.5
#
# For convenience, alisas (but don't sym-link) python & pip to python3 & pip3 as recommended in:
# http://askubuntu.com/questions/351318/changing-symlink-python-to-python3-causes-problems
RUN apt-get install -y --no-install-recommends python3.5 python3.5-dev python3-pip
RUN pip3 install --no-cache-dir --upgrade pip setuptools
RUN echo "alias python='python3'" >> /root/.bash_aliases
RUN echo "alias pip='pip3'" >> /root/.bash_aliases
# Pillow and it's dependencies
RUN apt-get install -y --no-install-recommends libjpeg-dev zlib1g-dev
RUN pip3 --no-cache-dir install Pillow
# Common libraries
RUN pip3 --no-cache-dir install \
    numpy scipy sklearn scikit-image pandas matplotlib

#
# Jupyter Notebook
#
RUN pip3 --no-cache-dir install jupyter
# Allow access from outside the container, and skip trying to open a browser.
RUN mkdir /root/.jupyter
RUN echo "c.NotebookApp.ip = '*'" \
         "\nc.NotebookApp.open_browser = False" \
         >> /root/.jupyter/jupyter_notebook_config.py
EXPOSE 8888

#
# Tensorflow 0.11 - CPU only
#
RUN pip3 install --no-cache-dir --upgrade \
    https://storage.googleapis.com/tensorflow/linux/cpu/tensorflow-0.11.0-cp35-cp35m-linux_x86_64.whl
# Expose port for TensorBoard
EXPOSE 6006

#
# OpenCV 3.1
#
# Dependencies
RUN apt-get install -y --no-install-recommends \
    libjpeg8-dev libtiff5-dev libjasper-dev libpng12-dev \
    libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libgtk2.0-dev
# Get source from github
RUN git clone -b 3.1.0 --depth 1 https://github.com/Itseez/opencv.git /root/opencv
# Compile
RUN cd /root/opencv && mkdir build && cd build && \
    cmake -D CMAKE_INSTALL_PREFIX=/usr/local \
          -D BUILD_TESTS=OFF \
          -D BUILD_PERF_TESTS=OFF \
          -D PYTHON_DEFAULT_EXECUTABLE=$(which python3) \
          .. && \
    make -j"$(nproc)" && \
    make install

#
# Caffe
#
# Dependencies
RUN apt-get install -y --no-install-recommends \
    cmake libprotobuf-dev libleveldb-dev libsnappy-dev libopencv-dev \
    libhdf5-serial-dev protobuf-compiler liblmdb-dev libgoogle-glog-dev
RUN apt-get install -y --no-install-recommends libboost-all-dev
# Get source. Use master branch because the latest stable release (rc3) misses critical fixes.
RUN git clone -b master --depth 1 https://github.com/BVLC/caffe.git /root/caffe
# Python dependencies
RUN pip3 --no-cache-dir install -r /root/caffe/python/requirements.txt
# Compile
RUN cd /root/caffe && mkdir build && cd build && \
    cmake -D CPU_ONLY=ON -D python_version=3 -D BLAS=open -D USE_OPENCV=ON .. && \
    make -j"$(nproc)" all && \
    make install
# Enivronment variables
ENV PYTHONPATH=/root/caffe/python:$PYTHONPATH \
	PATH=/root/caffe/build/tools:$PATH
# Fix: old version of python-dateutil breaks caffe. Update it.
RUN pip3 install --no-cache-dir python-dateutil --upgrade

#
# Java
#
# Install JDK (Java Development Kit), which includes JRE (Java Runtime
# Environment). Or, if you just want to run Java apps, you can install
# JRE only using: apt install default-jre
RUN apt-get install -y --no-install-recommends default-jdk

#
# Keras
#
RUN pip install keras

#
# Bazel
#
# Add apt-get custom repository
RUN echo "deb [arch=amd64] http://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list && \
    curl https://bazel.build/bazel-release.pub.gpg | apt-key add -
# Updat apt-get and install Bazel
RUN apt-get update && \
    apt-get install -y --no-install-recommends bazel
# Workarounds to allow Bazel to run in Docker:
# 1. Sandboxing issue: https://github.com/bazelbuild/bazel/issues/134
# 2. Limit memory usage to avoid out of memory errors.
RUN echo "startup --batch" >> /root/.bazelrc && \
    echo "build --spawn_strategy=standalone --genrule_strategy=standalone" >> /root/.bazelrc && \
    echo "build --local_resources 3072,1,1" >> /root/.bazelrc

#
# Tensorflow Source code
#
# Source code needed to compile C++ or to use some tools not available in the PIP install yet.
# Version v0.11.0 has a bug that treaks compiling, so using master branch instead.
# https://github.com/tensorflow/tensorflow/issues/5143
RUN git clone -b master --recursive --depth 1 https://github.com/tensorflow/tensorflow.git /root/tensorflow
# Swig. Needed to compile Tensorflow.
RUN apt-get install -y --no-install-recommends swig
# Run ./configure in tensorflow folder. Required to compile Tensorflow.
# Typically this is done manually. But here we simulate it to automate the process.
# We set the python3 paths, disable GPU, skip Google Cloud services, and skip Hadoop. 
WORKDIR /root/tensorflow
RUN echo "/usr/bin/python3\n\n\n/usr/local/lib/python3.5/dist-packages/\n\n" | ./configure
# Compile. No need to bulid the pip package because we already installed Tensorflow earlier.
RUN bazel build -c opt //tensorflow/tools/pip_package:build_pip_package

#
# Cleanup
#
RUN apt-get clean && \
    apt-get autoremove

WORKDIR "/root"
CMD ["/bin/bash"]
