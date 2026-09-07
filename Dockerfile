FROM ubuntu:22.04

# Avoid prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install prerequisites for Python and Flutter
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    python3 \
    python3-pip \
    python3-venv \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set up Flutter with shallow clone to save time and bandwidth
ENV FLUTTER_HOME=/opt/flutter
ENV PATH=${FLUTTER_HOME}/bin:${PATH}

RUN git clone --depth 1 -b stable https://github.com/flutter/flutter.git ${FLUTTER_HOME} \
    && git config --global --add safe.directory ${FLUTTER_HOME} \
    && flutter config --no-analytics \
    && flutter config --enable-web \
    && flutter precache --web

WORKDIR /app

# 1. Cache Python dependencies
COPY backend/requirements.txt /app/backend/requirements.txt
RUN pip3 install --no-cache-dir -r /app/backend/requirements.txt

# 2. Cache Flutter dependencies
COPY frontend/pubspec.* /app/frontend/
WORKDIR /app/frontend
RUN flutter pub get

# 3. Copy remaining source code
WORKDIR /app
COPY backend /app/backend
COPY frontend /app/frontend

EXPOSE 5000
EXPOSE 8080

CMD ["/bin/bash"]
