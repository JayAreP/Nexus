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
    git \
    gnupg \
    jq \
    lsb-release \
    nginx \
    software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI
RUN curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
       | tee /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update && apt-get install -y azure-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Google Cloud CLI
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
       | tee /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update && apt-get install -y google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip /tmp/awscliv2.zip -d /tmp/aws-installer \
    && /tmp/aws-installer/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws-installer \
    && aws --version

# Install ttyd (web terminal)
RUN curl -fsSL https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

# Install Terraform
RUN curl -fsSL https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip -o terraform.zip \
    && unzip terraform.zip -d /usr/local/bin/ \
    && rm terraform.zip \
    && terraform --version

# Install Bicep CLI
RUN curl -fsSL https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64 -o /usr/local/bin/bicep \
    && chmod +x /usr/local/bin/bicep \
    && bicep --version

# Install required PowerShell modules
RUN pwsh -Command "Install-Module -Name Pode -Force -Scope AllUsers -AllowClobber"
RUN pwsh -Command "Install-Module -Name Az.Storage -Force -Scope AllUsers -AllowClobber"
RUN pwsh -Command "Install-Module -Name Az.Accounts -Force -Scope AllUsers -AllowClobber"
RUN pwsh -Command "Install-Module -Name Az.Resources -Force -Scope AllUsers -AllowClobber"

# Create persistent mount points for runtime-installed modules
RUN mkdir -p /mnt/nexus/ps-modules /mnt/nexus/py-packages

# Copy application files
COPY Server.ps1 /app/
COPY Scripts/ /app/Scripts/
COPY public/ /app/public/
COPY version.txt /app/
# Configure nginx as reverse proxy (single-port entry point)
COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN rm -f /etc/nginx/sites-enabled/default

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
    && echo 'echo "  Available: pwsh, python3, terraform, az, aws, gcloud, bash"' >> /home/sandbox/.bashrc \
    && echo 'echo ""' >> /home/sandbox/.bashrc \
    && chown sandbox:sandbox /home/sandbox/.bashrc

EXPOSE 8080

ENV POWERSHELL_TELEMETRY_OPTOUT=1
ENV PYTHONPATH="/mnt/nexus/py-packages"
ENV PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/az/bin:${PATH}"
ENV TMPDIR="/tmp"

# Add /mnt/nexus paths to PowerShell and Python for all users (including sandbox)
RUN echo '$env:PSModulePath += ":/mnt/nexus/ps-modules"' >> /opt/microsoft/powershell/7-lts/profile.ps1
RUN echo '/mnt/nexus/py-packages' > /usr/lib/python3/dist-packages/nexus_paths.pth

CMD ["pwsh", "-File", "/app/Server.ps1"]
