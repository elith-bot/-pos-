FROM ubuntu:22.04

# Avoid tzdata prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install prerequisites for Python and Flutter
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Set up Flutter
ENV FLUTTER_HOME=/opt/flutter
ENV PATH=${FLUTTER_HOME}/bin:${PATH}
RUN git clone https://github.com/flutter/flutter.git -b stable ${FLUTTER_HOME}
RUN flutter config --enable-web
RUN flutter precache

# Set up the working directory
WORKDIR /app

# Copy the backend code and install dependencies
COPY backend /app/backend
RUN pip3 install --no-cache-dir -r /app/backend/requirements.txt

# Copy the frontend code and fetch dependencies
COPY frontend /app/frontend
WORKDIR /app/frontend
RUN flutter pub get

# Build the Flutter web app (Optional: if you just want to serve the static files)
# RUN flutter build web

WORKDIR /app

# Expose ports (e.g., 5000 for backend, 8080 for frontend or whatever you use)
EXPOSE 5000
EXPOSE 8080

# The default command can be a bash shell, or a script that runs both backend and frontend.
CMD ["/bin/bash"]
