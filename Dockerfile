ARG PYTHON_VERSION=3.11.6
ARG PILOT_VERSION=3.10.4.12

FROM docker.io/almalinux:9.4

ARG PYTHON_VERSION
ARG PILOT_VERSION

RUN dnf update -y
RUN dnf install -y epel-release
RUN dnf install -y gcc make voms-clients apptainer wget openssl-devel bzip2-devel libffi-devel zlib-devel \
    which nordugrid-arc-client emacs unzip

# install python
RUN mkdir /tmp/python && cd /tmp/python && \
    wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz && \
    tar -xzf Python-*.tgz && rm -f Python-*.tgz && \
    cd Python-* && \
    ./configure  && \
    make altinstall && \
    echo /usr/local/lib > /etc/ld.so.conf.d/local.conf && ldconfig && \
    cd / && rm -rf /tmp/pyton

RUN  dnf clean all && rm -rf /var/cache/dnf

# setup venv with pythonX.Y
RUN python$(echo ${PYTHON_VERSION} | sed -E 's/\.[0-9]+$//') -m venv /opt/pilot

RUN /opt/pilot/bin/pip install --no-cache-dir -U pip setuptools
RUN /opt/pilot/bin/pip install --no-cache-dir -U rucio-clients psutil

RUN mkdir /pilot
WORKDIR /pilot

ARG WRAPPER_NAME=runpilot2-wrapper.sh

# copy the wrapper script
COPY ${WRAPPER_NAME} .
RUN chmod +x ${WRAPPER_NAME}

# download pilot tarball
RUN wget -O pilot3.tar.gz https://github.com/PanDAWMS/pilot3/archive/refs/tags/${PILOT_VERSION}.tar.gz && \
    tar xvfz pilot3.tar.gz && mv pilot3-${PILOT_VERSION} pilot3

# create entrypoint script
RUN echo '#!/bin/bash' > entrypoint.sh && \
    echo 'source /opt/pilot/bin/activate' >> entrypoint.sh && \
    echo './'${WRAPPER_NAME}' $@' >> entrypoint.sh && \
    chmod +x entrypoint.sh

ENTRYPOINT ["/pilot/entrypoint.sh"]
