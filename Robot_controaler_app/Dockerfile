# Use Ubuntu as the base OS
FROM ubuntu:22.04

# Stop interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Add i386 architecture for 32-bit libraries required by Android SDK
RUN dpkg --add-architecture i386

# Update system and install essential packages, tools, and libraries
RUN apt-get update -y && \
    apt-get install -y \
    curl git unzip xz-utils zip libglu1-mesa \
    openjdk-17-jdk wget libc6:i386 libncurses5:i386 \
    libstdc++6:i386 lib32z1 libbz2-1.0:i386 \
    clang cmake ninja-build pkg-config libgtk-3-dev \
    && rm -rf /var/lib/apt/lists/*

# Set up Android SDK paths
ENV ANDROID_HOME=/opt/android/sdk
ENV ANDROID_SDK_ROOT=/opt/android/sdk
ENV PATH=${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools

# Download and install Android Command Line Tools
WORKDIR /opt/android
RUN wget -q "https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip" -O cmdline-tools.zip \
    && unzip -q cmdline-tools.zip \
    && rm cmdline-tools.zip

# Move the downloaded cmdline-tools to the correct `latest` folder structure required by sdkmanager
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools/latest \
    && mv cmdline-tools/* ${ANDROID_HOME}/cmdline-tools/latest/ || true \
    && rm -rf cmdline-tools

# Accept licenses and install Android packages
RUN yes | sdkmanager --licenses
# Note: For flutter we need platforms, platform-tools, and build-tools
RUN sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# Install Flutter SDK
ENV FLUTTER_HOME=/opt/flutter
ENV PATH=${PATH}:${FLUTTER_HOME}/bin
WORKDIR /opt
RUN git clone https://github.com/flutter/flutter.git -b stable ${FLUTTER_HOME}

# Pre-download Flutter development binaries
RUN flutter precache

# Accept Android SDK licenses for Flutter
RUN yes | flutter doctor --android-licenses

# Set git config to trust the flutter folder
RUN git config --global --add safe.directory /opt/flutter

# Verify the completed setup
RUN flutter doctor -v

# The workspace will be mounted to /app
WORKDIR /app
