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

# Install ttyd (web terminal)
RUN curl -fsSL https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

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

# Install NLS modules for workflow scripts
COPY NLS/powershell/NLS/ /opt/microsoft/powershell/7-lts/Modules/NLS/1.0.0/
COPY NLS/python/ /tmp/nls-pkg/
RUN pip3 install --target /usr/lib/python3/dist-packages /tmp/nls-pkg/ && rm -rf /tmp/nls-pkg/

# Create conf directory for local config
RUN mkdir -p /app/conf

# Create restricted sandbox user
RUN useradd -m -s /bin/bash -d /home/sandbox sandbox \
    && mkdir -p /home/sandbox/workspace \
    && chown -R sandbox:sandbox /home/sandbox

# Create sandbox bashrc with custom prompt and welcome message
RUN echo 'export PS1="\[\e[33m\]sandbox\[\e[0m\]:\[\e[36m\]\w\[\e[0m\]$ "' > /home/sandbox/.bashrc \
    && echo 'cd /home/sandbox/workspace' >> /home/sandbox/.bashrc \
    && echo 'echo ""' >> /home/sandbox/.bashrc \
    && echo 'echo "  Nexus Sandbox - Restricted Test Environment"' >> /home/sandbox/.bashrc \
    && echo 'echo "  Working directory: /home/sandbox/workspace"' >> /home/sandbox/.bashrc \
    && echo 'echo "  Available: pwsh, python3, terraform, bash"' >> /home/sandbox/.bashrc \
    && echo 'echo ""' >> /home/sandbox/.bashrc \
    && chown sandbox:sandbox /home/sandbox/.bashrc

EXPOSE 8080
EXPOSE 7681

ENV POWERSHELL_TELEMETRY_OPTOUT=1

CMD ["pwsh", "-File", "/app/Server.ps1"]
