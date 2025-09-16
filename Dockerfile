FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /work

# Базовые утилиты + сетевые сканеры
RUN apt update && apt install -y --no-install-recommends \
    ca-certificates curl iproute2 iputils-ping netcat-traditional dnsutils \
    nmap masscan whatweb nikto sslscan \
    hydra hydra-gtk wordlists \
    miniupnpc \
    python3 python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Дополнительно: удобный алиас nc -> ncat (опционально)
RUN update-alternatives --set nc /bin/nc.traditional || true

RUN mkdir -p /work/reports

ENTRYPOINT ["/bin/bash"]
