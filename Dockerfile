FROM nvidia/cuda:8.0-cudnn6-devel-ubuntu16.04

MAINTAINER Majid Laali <majid@elementai.com>

# Install Anaconda, we do this so that we are free to choose which python version we want to use.
# We chose to use python 3.6, check these docker for other version: 

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update --fix-missing && apt-get install -y wget bzip2 ca-certificates \
    libglib2.0-0 libxext6 libsm6 libxrender1 \
    git mercurial subversion

RUN echo 'export PATH=/opt/conda/bin:$PATH' > /etc/profile.d/conda.sh && \
    wget --quiet https://repo.continuum.io/miniconda/Miniconda3-4.3.14-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh

ENV PATH /opt/conda/bin:$PATH

# Install the latest version of tensorflow with the GPU support.
RUN pip install tensorflow-gpu

COPY setup.py /eai/

COPY requirements.txt /eai/
RUN conda install --yes --file /eai/requirements.txt

WORKDIR /eai
ENV HOME /eai

