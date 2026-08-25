# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:44 AS builder

# [OTIMIZAÇÃO 1]: Configura o DNF5 para manter os RPMs baixados nesta camada
RUN sed -i 's/keepcache = false/keepcache = true/g' /etc/dnf/dnf5.conf

RUN KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install "kernel-devel-${KERNEL_VERSION}" wget && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda && \
    akmods --force --kernels "$KERNEL_VERSION"

# Segundo estágio, imagem final com driver NVIDIA versão 580 Negativo17
FROM quay.io/fedora/fedora-bootc:44 AS final

# [OTIMIZAÇÃO 2]: Ativa cache no estágio final também, pois ele faz downloads novos
RUN sed -i 's/keepcache = false/keepcache = true/g' /etc/dnf/dnf5.conf

# 1. Configuração de repostórios e instalação de Kernel Extras + NVIDIA
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo /etc/yum.repos.d/ 
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm /tmp/nvidia/ 
COPY 10-nvidia-args.toml nvidia-power.conf nvidia_packages /tmp/sysconfig/ 

RUN kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install --setopt=tsflags=nodocs "kernel-modules-extra-${kver}" && \
    dnf5 download --destdir=/tmp/nvidia nvidia-kmod-common nvidia-driver-cuda && \
    rpm -vi --nodeps /tmp/nvidia/nvidia-kmod-common*.rpm && \
    rpm -vi --nodeps /tmp/nvidia/nvidia-driver-cuda*.rpm && \
    mv -v /tmp/sysconfig/10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml && \
    mv -v /tmp/sysconfig/nvidia-power.conf /etc/modprobe.d/ && \
    grep -v '^#' /tmp/sysconfig/nvidia_packages | tr '\n' ' ' | xargs dnf5 install --setopt=tsflags=nodocs -y && \
    dnf5 -y install /tmp/nvidia/kmod-nvidia-*.rpm && \
    rm -rf /tmp/nvidia
    # [OTIMIZAÇÃO 3]: Removeu-se o "dnf5 clean all" e a exclusão da pasta de cache daqui.
    # O comando "rechunk" no workflow já vai expurgar tudo isso na imagem de distribuição.

# 5. Validação do bootc
RUN bootc container lint