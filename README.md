## IDP – Zimbra on AWS via LocalStack

This repository contains a portfolio-grade **Internal Developer Platform (IDP)** that automates the deployment of **Zimbra** on **AWS** (using **LocalStack** for local/cloud-like development) with integrated **OpenTelemetry (OTel)** monitoring.

### Objectives

- Provide an opinionated but extensible platform to:
  - **Provision cloud infrastructure** (networking, compute, storage) in a reproducible way.
  - **Deploy and manage Zimbra** using **Crossplane** compositions.
  - **Simulate AWS** locally with **LocalStack** for fast feedback loops.
  - **Expose observability signals** (metrics, traces, logs) via **OTel-compatible tooling**.

### High-Level Architecture

- **Crossplane**
  - `crossplane/providers` – Provider configurations for AWS and LocalStack.
  - `crossplane/compositions` – Compositions and XRDs that describe Zimbra and its dependencies as higher-level abstractions.

- **Infrastructure**
  - `infrastructure` – Base networking and shared infrastructure (VPCs, subnets, security groups, etc.), primarily described using Terraform and/or Crossplane-managed resources.

- **Observability**
  - `observability` – OpenTelemetry configuration and related assets (collectors, exporters, dashboards configuration files, etc.).

- **Automation Scripts**
  - `scripts` – Helper scripts (e.g. environment bootstrapping, localstack helpers, demo flows). The `setup.sh` script will orchestrate local bootstrap tasks.

### Repository Layout

- `crossplane/providers/` – Provider configurations and credentials references (non-sensitive, templated).
- `crossplane/compositions/` – Crossplane XRDs and Compositions describing Zimbra and its dependencies.
- `infrastructure/` – Terraform modules or Crossplane resources for base infrastructure.
- `observability/` – OTel collector configuration, dashboards and alerting templates.
- `scripts/` – Automation and helper scripts (e.g., `setup.sh`).

### Getting Started (High-Level)

1. **Clone the repository** and ensure you have:
   - Docker / container runtime
   - LocalStack
   - kubectl
   - Crossplane CLI (or access to a Crossplane control plane)

2. **Bootstrap the environment** (local or remote):
   - Start LocalStack.
   - Apply Crossplane provider configurations in `crossplane/providers/`.
   - Apply base infrastructure definitions in `infrastructure/`.

3. **Deploy Zimbra via Crossplane compositions**:
   - Apply the XRDs and Compositions from `crossplane/compositions/`.

4. **Enable observability**:
   - Deploy OTel collector and related configuration from `observability/`.
   - Connect your preferred backend (e.g., Tempo, Prometheus, Grafana, etc.).

### Notes

- This project is designed as a **showcase portfolio**. It favours clarity and structure over exhaustive production-hardening.
- Secrets and credentials are **not** stored in this repository; use your own secure secret management solution (e.g., AWS Secrets Manager, SOPS, or Vault).

