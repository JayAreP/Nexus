# Nexus - Automation Sequencer
# PowerShell + Azure Modules + PODE Web Server

FROM mcr.microsoft.com/powershell:lts-ubuntu-22.04

WORKDIR /app

# Install Python, pip, and system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    unzip \
    curl \
    gnupg \
    software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN curl -fsSL https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip -o terraform.zip \
    && unzip terraform.zip -d /usr/local/bin/ \
    && rm terraform.zip \
    && terraform --version

# Install required PowerShell modules
RUN pwsh -Command "Install-Module -Name Pode -Force -Scope AllUsers -AllowClobber"
RUN pwsh -Command "Install-Module -Name Az.Storage -Force -Scope AllUsers -AllowClobber"
RUN pwsh -Command "Install-Module -Name Az.Accounts -Force -Scope AllUsers -AllowClobber"
RUN pwsh -Command "Install-Module -Name Az.Resources -Force -Scope AllUsers -AllowClobber"

# Copy application files
COPY Server.ps1 /app/
COPY Scripts/ /app/Scripts/
COPY public/ /app/public/
COPY version.txt /app/

# Create conf directory for local config
RUN mkdir -p /app/conf

EXPOSE 8080

ENV POWERSHELL_TELEMETRY_OPTOUT=1

CMD ["pwsh", "-File", "/app/Server.ps1"]
