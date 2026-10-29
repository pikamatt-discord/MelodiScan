FROM python:3.11-slim-bookworm

ARG AUDIVERIS_VERSION=5.10.0
ARG AUDIVERIS_SHA256=25cc19fe995a14e9e9ab54e04d1dba92b3fbab21f706c5a5ce0425738c4adfd7

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    git \
    build-essential \
    curl \
    ca-certificates \
    libasound2 \
    libbsd0 \
    libfontconfig1 \
    libfreetype6 \
    libgtk-3-0 \
    libmd0 \
    libx11-6 \
    libxau6 \
    libxcb1 \
    libxdmcp6 \
    libxext6 \
    libxi6 \
    libxrender1 \
    libxtst6 \
    xdg-utils \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    test "$(dpkg --print-architecture)" = "amd64"; \
    package="/tmp/audiveris-${AUDIVERIS_VERSION}.deb"; \
    curl -fsSL "https://github.com/Audiveris/audiveris/releases/download/${AUDIVERIS_VERSION}/Audiveris-${AUDIVERIS_VERSION}-ubuntu22.04-x86_64.deb" -o "$package"; \
    echo "${AUDIVERIS_SHA256}  ${package}" | sha256sum -c -; \
    apt-get update; \
    dpkg-deb --extract "$package" /; \
    launcher="$(find /opt -path '*/bin/*' -iname 'audiveris' -print -quit)"; \
    test -n "$launcher"; \
    test -x "$launcher"; \
    ln -s "$launcher" /usr/local/bin/audiveris; \
    audiveris -help >/dev/null; \
    rm -f "$package"; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app /app/app

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
