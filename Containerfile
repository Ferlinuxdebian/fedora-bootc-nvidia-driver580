# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:44 AS builder

# Adiciona o parâmetro de cache diretamente no arquivo existente do DNF5
RUN echo "keepcache=true" >> /etc/dnf/dnf.conf

RUN dnf5 -y upgrade kernel* --refresh & \
    KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install "kernel-devel-${KERNEL_VERSION}" wget && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda && \
    akmods --force --kernels "$KERNEL_VERSION"

# Segundo estágio, imagem final com driver NVIDIA versão 580 Negativo17
FROM quay.io/fedora/fedora-bootc:44 AS final

# Adiciona o parâmetro de cache na imagem final também
RUN echo "keepcache=true" >> /etc/dnf/dnf.conf

# 1. Configuração de repostórios e instalação de Kernel Extras + NVIDIA
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo /etc/yum.repos.d/ 
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm /tmp/nvidia/ 
COPY 10-nvidia-args.toml nvidia-power.conf nvidia_packages /tmp/sysconfig/ 

RUN dnf5 -y upgrade kernel* --refresh && \
    kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install --setopt=tsflags=nodocs "kernel-modules-extra-${kver}" && \
    dnf5 download --destdir=/tmp/nvidia nvidia-kmod-common nvidia-driver-cuda && \
    rpm -vi --nodeps /tmp/nvidia/nvidia-kmod-common*.rpm && \
    rpm -vi --nodeps /tmp/nvidia/nvidia-driver-cuda*.rpm && \
    mv -v /tmp/sysconfig/10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml && \
    mv -v /tmp/sysconfig/nvidia-power.conf /etc/modprobe.d/ && \
    grep -v '^#' /tmp/sysconfig/nvidia_packages | tr '\n' ' ' | xargs dnf5 install --setopt=tsflags=nodocs -y && \
    dnf5 -y install /tmp/nvidia/kmod-nvidia-*.rpm && \
    rm -rf /tmp/nvidia

# 5. Validação do bootc
RUN bootc container lint
