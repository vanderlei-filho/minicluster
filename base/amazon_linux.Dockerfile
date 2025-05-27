FROM amazonlinux:2023

# Setup base environment variables
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install base dependencies
RUN dnf -y update && \
    dnf -y upgrade && \
    dnf group install -y "Development Tools" && \
    dnf install -y \
        tmux \
        gcc gcc-c++ \
        clang clang-tools-extra \
        pkg-config automake autoconf libtool \
        hwloc hwloc-devel numactl-devel \
        kernel-devel \
        kernel-headers \
        wget \
        tar \
        bzip2 \
        openssh-clients \
        openssh-server && \
    dnf clean all

# Create /shared directory
RUN mkdir -p /shared && chmod 755 /shared

# Configure SSH for MPI communication
RUN ssh-keygen -A && \
    mkdir -p /root/.ssh && \
    ssh-keygen -t rsa -f /root/.ssh/id_rsa -N "" && \
    cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh

# Configure SSH client
RUN echo 'Host *' > /root/.ssh/config && \
    echo '    StrictHostKeyChecking no' >> /root/.ssh/config && \
    echo '    UserKnownHostsFile /dev/null' >> /root/.ssh/config && \
    echo '    LogLevel ERROR' >> /root/.ssh/config && \
    chmod 600 /root/.ssh/config

# Configure SSH daemon
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Install HWLOC from source
RUN cd /tmp && \
    wget https://download.open-mpi.org/release/hwloc/v2.12/hwloc-2.12.0.tar.bz2 && \
    tar -xf hwloc-2.12.0.tar.bz2 && \
    cd hwloc-2.12.0 && \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /tmp/hwloc-*

# Install UCX (Unified Communication X)
RUN dnf install -y git && \
    cd /tmp && \
    git clone https://github.com/openucx/ucx.git && \
    cd ucx && \
    git checkout v1.18.x && \
    ./autogen.sh && \
    mkdir build && cd build && \
    ../contrib/configure-release --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /tmp/ucx

# Install OpenMPI from source
RUN cd /tmp && \
    wget https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-5.0.7.tar.bz2 && \
    tar xf openmpi-5.0.7.tar.bz2 && \
    cd openmpi-5.0.7 && \
    ./configure \
      --prefix=/usr/local \
      --enable-mpi-fortran \
      --enable-mca-no-build=btl-uct \
      --enable-shared \
      --enable-static \
      --with-ucx && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /tmp/openmpi-*

# Unified environment setup for HWLOC, UCX, and OpenMPI
RUN echo '#!/bin/bash' > /etc/profile.d/hpc_libs.sh && \
    echo '# System-wide environment variables for HPC libraries (HWLOC, UCX, OpenMPI)' >> /etc/profile.d/hpc_libs.sh && \
    echo 'export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"' >> /etc/profile.d/hpc_libs.sh && \
    echo 'export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' >> /etc/profile.d/hpc_libs.sh && \
    echo 'export PATH="/usr/local/bin${PATH:+:$PATH}"' >> /etc/profile.d/hpc_libs.sh && \
    chmod +x /etc/profile.d/hpc_libs.sh

# Set unified environment variables for build and runtime
ENV PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig"
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64"
ENV PATH="/usr/local/bin:$PATH"

# Create startup script for SSH and shell
RUN echo '#!/bin/bash' > /usr/local/bin/start-container.sh && \
    echo '# Start SSH daemon' >> /usr/local/bin/start-container.sh && \
    echo '/usr/sbin/sshd -D &' >> /usr/local/bin/start-container.sh && \
    echo 'SSH_PID=$!' >> /usr/local/bin/start-container.sh && \
    echo '' >> /usr/local/bin/start-container.sh && \
    echo '# Wait for SSH to be ready' >> /usr/local/bin/start-container.sh && \
    echo 'sleep 2' >> /usr/local/bin/start-container.sh && \
    echo '' >> /usr/local/bin/start-container.sh && \
    echo '# Start interactive shell or execute command' >> /usr/local/bin/start-container.sh && \
    echo 'if [ $# -eq 0 ]; then' >> /usr/local/bin/start-container.sh && \
    echo '    exec /bin/bash' >> /usr/local/bin/start-container.sh && \
    echo 'else' >> /usr/local/bin/start-container.sh && \
    echo '    exec "$@"' >> /usr/local/bin/start-container.sh && \
    echo 'fi' >> /usr/local/bin/start-container.sh && \
    chmod +x /usr/local/bin/start-container.sh

# Set working directory
WORKDIR /shared

# Default command starts SSH and bash
CMD ["/usr/local/bin/start-container.sh"]
