# escape=`

ARG BASE_IMAGE
ARG TOOLING_IMAGE
## ARG SOLUTION_IMAGE

# FROM ${SOLUTION_IMAGE} as solution
FROM ${TOOLING_IMAGE} as tooling
FROM BASE_IMAGE

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

COPY .\Run-W3SVCService.ps1 C:\

WORKDIR C:\inetpub\wwwroot

# Copy development tools and entrypoint
COPY --from=tooling C:\tools C:\tools

COPY .\wwwroot .\