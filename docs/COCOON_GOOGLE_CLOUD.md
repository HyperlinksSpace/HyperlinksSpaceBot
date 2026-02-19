# Running Cocoon (origin branch, no local changes) on Google Cloud

This guide covers running **upstream Cocoon** (origin branch, unmodified) on **Google Cloud** as a **client** node. The client exposes an OpenAI-compatible HTTP API your app can use for AI generations (via the Cocoon network). Proxy and worker require Intel TDX hardware and are not covered here for GCP.

---

## Index

1. [Overview](#overview)
2. [Plan: Moving to full Cocoon run](#plan-moving-to-full-cocoon-run) — steps to run worker + client + router
3. [Prerequisites](#prerequisites)
4. [Set up a test instance in your project](#set-up-a-test-instance-in-your-project) — create the VM (one-time)
5. [Environment variables (client only)](#environment-variables-client-only) — obligatory vs optional, where to set on GCP
6. [Option A: Compute Engine VM](#option-a-compute-engine-vm) — full VM workflow (build, run, envs)
7. [Option B: Cloud Run (container)](#option-b-cloud-run-container)
8. [HTTPS and production](#https-and-production)
9. [Connect your app](#connect-your-app)
10. [Troubleshooting](#troubleshooting)

---

## Overview

| Component | Runs on GCP? | Notes |
|-----------|--------------|--------|
| **Client** | Yes | HTTP API on port 10000, connects to Cocoon network |
| **Router** | Yes | RA-TLS helper; runs alongside client |
| Proxy / Worker | No (on GCP) | Require Intel TDX; use Cocoon network’s existing proxies/workers |

You will:

- Use a **clean Cocoon repo** (origin branch, no HyperlinksSpaceBot patches).
- Build **client-runner**, **router**, and **cocoon-subst** on Linux (GCP VM or Docker).
- Run **client + router** so the client is reachable over HTTP(S).
- Point your AI backend’s `COCOON_CLIENT_URL` at this deployment.

---

## Plan: Moving to full Cocoon run

To run the **full** Cocoon stack (worker + client + router) on Google Cloud, follow this order.

| Phase | What to do |
|-------|------------|
| **1. GCP billing & quota** | Enable billing on your project. Request **GPU quota**: [Quotas](https://console.cloud.google.com/iam-admin/quotas) → set “Metric” to **All quotas**; filter by `NVIDIA_H100` or `GPUS_PER_GPU_FAMILY`. Edit the **GPUS_PER_GPU_FAMILY** (or **NVIDIA H100**) quota for region `us-central1` and request at least **1**. For Spot VMs you may also need **PREEMPTIBLE_NVIDIA_H100_GPUS** in that region. Submit and wait for approval (often 24–48 hours). |
| **2. Create full-setup VM** | Use the [**Full setup (worker-capable)**](#4-create-the-vm-instance) create command: A3 + TDX + H100 (Spot), zone `us-central1-a` (or `us-east5-a` / `europe-west4-c`). Same steps 1–3 (project, zone, optional default zone), then the `a3-highgpu-1g` command in step 4. |
| **3. Firewall** | Create rules for client (port 10000) and optionally worker stats (port 12000) as in [step 5](#5-open-firewall-for-the-cocoon-client-port-10000). |
| **4. Enable confidential GPU on VM** | SSH into the VM. Follow GCP: [Enable confidential computing mode on the GPU](https://cloud.google.com/confidential-computing/confidential-vm/docs/create-a-confidential-vm-instance-with-gpu#enable-confidential-computing-mode-on-the-gpu) (install drivers, LKCA, persistence mode, reboot). |
| **5. Cocoon worker setup** | On the VM: get TON wallet and keys; download [Cocoon worker distribution](https://docs.cocoon.org/for-gpu-owners#quick-start); run **seal-server** (required for production); create **worker.conf** (`owner_address`, `model`, `gpu`, `node_wallet_key`, `hf_token`, `ton_config`, `root_contract_address`); run worker with `./scripts/cocoon-launch worker.conf`. See [Cocoon For GPU Owners](https://docs.cocoon.org/for-gpu-owners). |
| **6. Client + router (same VM)** | On the same VM you can also build and run **client + router** (Option A from step 3 onward) so your app can call the Cocoon network; your worker will serve inference and you get daily TON payouts. |

Summary: **GCP** (quota → create A3 TDX+H100 VM → firewall → GPU confidential setup) → **Cocoon** (wallet, worker distro, seal-server, worker.conf, launch worker). No separate “plan” or subscription on Cocoon’s side—you just need the hardware, quota, and config.

---

## Prerequisites

- **Google Cloud** account and a project.
- **gcloud** CLI installed and logged in (`gcloud auth login`, `gcloud config set project $GC_HS_PROJECT_ID`).
- For **real TON** (production): TON wallet, `OWNER_ADDRESS`, `NODE_WALLET_KEY`, and a TON config file (e.g. `spec/mainnet-full-ton-config.json`).
- For **testing**: fake-TON mode needs no real wallet.

### Prerequisites vs. Cocoon “For GPU Owners” guide

The [Cocoon For GPU Owners](https://docs.cocoon.org/for-gpu-owners) guide defines prerequisites for **running workers** (contributing GPU inference to the network). Aligning with that guide:

| Prerequisite (GPU Owner guide) | Client-only on GCP (this doc) | Worker on GCP |
|--------------------------------|-------------------------------|----------------|
| **Linux server (6.16+ for full TDX)** | We use Ubuntu 22.04 LTS on the VM; kernel is older than 6.16. Sufficient for **client + router** only. | Worker guide expects 6.16+ for full TDX; GCP guest kernels are managed. |
| **Intel TDX–capable CPU** | Optional: use C3 TDX VM for a TDX-capable guest (client still works without TDX). | Worker requires TDX. GCP offers Intel TDX (C3) or **AMD SEV-SNP + confidential GPU** (A3 + H100); Cocoon worker stack may expect Intel TDX specifically. |
| **NVIDIA GPU with CC support (H100+)** | Not required for client. Optional: attach GPU (e.g. T4) for other workloads. | Required for worker. GCP has A3 Confidential VMs with H100 (GPU-TEE); confirm with Cocoon whether AMD SEV-SNP + H100 is supported. |
| **QEMU with TDX support (10.1+)** | Not used; we use managed Compute Engine VMs. | Worker guide assumes host-side QEMU+TDX for TDX guests; on GCP the hypervisor is managed. |
| **seal-server** (SGX enclave, key derivation) | Not required for client. | Required for production workers; runs on host, serves TDX guests. On GCP, no customer-run “host” in the same way—confirm with Cocoon for confidential GPU VMs. |
| **Enable TDX / Enable CC on NVIDIA GPU** | Not required for client. | Required for worker; see [Enabling Intel TDX](https://docs.cocoon.org/), [Enabling CC on NVIDIA GPU](https://docs.cocoon.org/). On GCP, confidential options are enabled via VM creation flags. |

**What to comply with for this guide (client-only):**

- **Linux:** Ubuntu 22.04 LTS on the VM (as in our create commands).
- **No TDX/GPU required** for the client; optional TDX (C3) or GPU (N1+T4) instance types are documented in [step 4](#4-create-the-vm-instance).
- **TON:** For production, have wallet, `OWNER_ADDRESS`, `NODE_WALLET_KEY`, and TON config; for testing, fake-TON is enough.

**If you want to run a Cocoon worker on GCP:** You would need a confidential GPU VM (e.g. A3 with H100) and to verify with Cocoon that their worker image and seal-server flow support GCP’s confidential GPU (AMD SEV-SNP + GPU-TEE) and managed host. This guide does not cover worker setup.

---

## Set up a test instance in your project

Yes — you need **one Compute Engine VM instance** in your Google Cloud project (e.g. your Test-tagged project like `hyperlinksspacebot`). Do this once; then you’ll SSH in to install Cocoon and run the client.

**1. Set project and region**

Set the Google Cloud project ID in your shell as **`GC_HS_PROJECT_ID`** (see [README ENVS](README.md#envs)). **Run these in the same terminal session** before creating the VM (otherwise the create command will fail):

```bash
export GC_HS_PROJECT_ID=hyperlinksspacebot
export ZONE=us-central1-a
export REGION=us-central1

gcloud config set project $GC_HS_PROJECT_ID
```

**2. Enable Compute Engine API**

Required to create VMs:

```bash
gcloud services enable compute.googleapis.com
```

**3. Set default zone (optional, for shorter commands)**

```bash
gcloud config set compute/zone $ZONE
gcloud config set compute/region $REGION
```

**4. Create the VM instance**

Use one of the following. Same name `cocoon-client` and tag for firewall; pick **default**, **TDX**, or **Nvidia GPU** depending on what you need.

**Default (no TDX, no GPU)** — client-only Cocoon, lowest cost:

```bash
gcloud compute instances create cocoon-client \
  --zone=us-central1-a \
  --machine-type=e2-medium \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=20GB \
  --tags=cocoon-client
```

**TDX (Intel Trust Domain Extensions)** — for Cocoon proxy/worker or confidential computing; requires C3 and a TDX-capable zone:

```bash
gcloud compute instances create cocoon-client \
  --zone=us-central1-a \
  --machine-type=c3-standard-4 \
  --confidential-compute-type=TDX \
  --maintenance-policy=TERMINATE \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=20GB \
  --tags=cocoon-client
```

If the zone does not support TDX, create in a [TDX-capable zone](https://cloud.google.com/confidential-computing/confidential-vm/docs/create-a-confidential-vm-instance#available-regions) or list images: `gcloud compute images list --filter="guestOsFeatures[].type:(TDX_CAPABLE)"`. Verify on the VM: `sudo dmesg | grep -i tdx`.

**Nvidia GPU (T4, L4, etc.)** — for **client + router only** or other GPU workloads (e.g. local inference). Cocoon **worker** cannot use these: it requires **H100+ with confidential computing**; GCP only offers confidential GPU with H100 (a3-highgpu-1g). If you have T4/L4 quota but not H100, use this option to run client + router (no worker, no TON payouts). Install [NVIDIA drivers](https://cloud.google.com/compute/docs/gpus/install-drivers-gpu) after first boot. Use a zone that has the GPU (e.g. `us-central1-a` for T4):

```bash
gcloud compute instances create cocoon-client \
  --zone=us-central1-a \
  --machine-type=n1-standard-4 \
  --accelerator=type=nvidia-tesla-t4,count=1 \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=40GB \
  --tags=cocoon-client
```

Check GPU availability: `gcloud compute accelerator-types list --filter="zone:us-central1-a"`. Boot disk ≥40GB is recommended for GPU driver install.

**Full setup (worker-capable)** — Intel TDX + NVIDIA H100 for running Cocoon **worker** (and client/router). Uses A3 Confidential VM; **costly** and requires [GPU quota](https://cloud.google.com/compute/resource-usage#gpu_quota) (e.g. preemptible H100). Supported zones: `us-central1-a`, `us-east5-a`, `europe-west4-c`. Create as **Spot** (preemptible) or use [Flex-start](https://cloud.google.com/confidential-computing/confidential-vm/docs/create-a-confidential-vm-instance-with-gpu#flex-start-model) for better availability:

```bash
gcloud compute instances create cocoon-client \
  --provisioning-model=SPOT \
  --confidential-compute-type=TDX \
  --machine-type=a3-highgpu-1g \
  --maintenance-policy=TERMINATE \
  --zone=us-central1-a \
  --image-project=ubuntu-os-cloud \
  --image-family=ubuntu-2204-lts \
  --boot-disk-size=100GB \
  --tags=cocoon-client
```

**Worker GPU is not replaceable:** Cocoon worker requires **H100+ with confidential computing**; T4, L4, and A100 do not meet that. GCP only supports confidential GPU with H100. To run a worker you must request H100 quota. To run only **client + router** with a GPU (e.g. for other workloads), use the **Nvidia GPU (T4/L4)** option above.

If the zone does not have capacity, try `us-east5-a` or `europe-west4-c`. After creation: [Enable confidential computing on the GPU](https://cloud.google.com/confidential-computing/confidential-vm/docs/create-a-confidential-vm-instance-with-gpu#enable-confidential-computing-mode-on-the-gpu) (install drivers, LKCA, persistence mode, reboot). Then follow the [Cocoon For GPU Owners](https://docs.cocoon.org/for-gpu-owners) guide (seal-server, worker.conf, cocoon-launch worker). Open firewall for worker stats if needed: `gcloud compute firewall-rules create allow-cocoon-worker --allow=tcp:12000 --target-tags=cocoon-client --source-ranges=0.0.0.0/0 --description="Cocoon worker HTTP stats"` (optional).

To **recreate** after deleting the instance: run steps 4–5 again (firewall rule is project-level and may already exist — if create fails with "already exists", skip or delete the rule first). Then run **step 7** and **config-ssh** (step 7 note) so your SSH config gets the new instance IP; re-add `User ASUS` and use forward slashes in `~/.ssh/config` for the new host entry if you use Remote-SSH in Cursor.

**5. Open firewall for the Cocoon client (port 10000)**

```bash
gcloud compute firewall-rules create allow-cocoon-client \
  --allow=tcp:10000 \
  --target-tags=cocoon-client \
  --source-ranges=0.0.0.0/0 \
  --description="Cocoon client HTTP API"
```

**6. Verify**

```bash
gcloud compute instances list --project=$GC_HS_PROJECT_ID
gcloud compute firewall-rules list --filter="name=allow-cocoon-client" --project=$GC_HS_PROJECT_ID
```

**About the warnings**

- **“Disk size of under [200GB] may result in poor I/O performance”** — That’s a generic note for heavy disk workloads. For the Cocoon **client** (mostly CPU/network, little disk I/O), 20GB is fine. You can ignore it or use e.g. `--boot-disk-size=30GB` if you want a bit more space.
- **“Disk size 20 GB is larger than image size 10 GB… resize root repartition manually”** — Ubuntu 22.04 usually **auto-resizes** the root partition on first boot to use the full disk. After your first SSH login, run `df -h /`; if the root filesystem already shows ~20GB, nothing to do. If it still shows ~10GB, run: `sudo growpart /dev/sda 1` then `sudo resize2fs /dev/sda1` (or the block device your root uses).

**7. SSH into the instance**

You need the **zone** so `gcloud` knows which instance to use (each VM lives in one zone). Use the same zone you set in step 1 and used in step 4 (e.g. `us-central1-a`). If you set the default zone in step 3, you can omit `--zone=$ZONE`. To look up the zone for an existing instance: run `gcloud compute instances list` and check the **ZONE** column, or in [Cloud Console](https://console.cloud.google.com/compute/instances) open Compute Engine → VM instances and read the Zone column.

```bash
gcloud compute ssh cocoon-client --zone=$ZONE --project=$GC_HS_PROJECT_ID
```

**First-time SSH:** You may see warnings that no gcloud SSH key exists — gcloud will run `ssh-keygen` and upload the public key to the project (one-time). If you see **"No zone specified. Using zone [us-central1-a]"**, that’s fine; gcloud is using the default zone. When prompted **"Store key in cache? (y/n)"**, type **y** and Enter to trust the VM’s host key and continue (safe for your own GCP instance).

**Use the VM terminal inside Cursor (Remote-SSH):** To have the remote shell as an ordinary terminal tab in Cursor instead of a separate window: (1) Run `gcloud compute config-ssh --project=$GC_HS_PROJECT_ID` once; this adds your instances to `~/.ssh/config` with a host name like `cocoon-client.us-central1-a.hyperlinksspacebot`. (2) In Cursor, open the Command Palette (Ctrl+Shift+P) → **Remote-SSH: Connect to Host...** → choose that host. (3) After connecting, open a terminal in Cursor (Ctrl+`) — it will be the VM shell. You can open folders on the VM and run commands there as usual.

On the VM you can then follow [Option A: Compute Engine VM](#option-a-compute-engine-vm) from step 3 (install dependencies, clone Cocoon, build, set envs, run client).

---

## Environment variables (client only)

These apply to the **Cocoon client** (and how `cocoon-launch` / your run script passes them into the client config). The client binary reads them via the rendered `client-config.json` (variables like `$OWNER_ADDRESS` are substituted at config-render time).

### Fake-TON (testing, no real blockchain)

| Variable | Obligatory? | Default / note | Where to set (GCP) |
|----------|-------------|-----------------|--------------------|
| **OWNER_ADDRESS** | **Yes** | None; script exits if missing | Config file `[node] owner_address=...`, or CLI `--owner-address`, or env `OWNER_ADDRESS` (if your launch path reads it). On VM: `export OWNER_ADDRESS=...` before running; or in systemd `Environment=`. On Cloud Run: Variables and secrets. |
| NODE_WALLET_KEY | No | Script default for fake-TON | Same as above. Optional for testing. |
| ROOT_CONTRACT_ADDRESS | No | Script default (e.g. `EQBcXvP9...`) | Override only if you use a custom root contract. |
| CLIENT_HTTP_PORT | No | 10000 | Only if you want a different port (e.g. 8080 for Cloud Run). |
| TON_CONFIG_FILE | No | Set by script to rendered path | Do not set for fake-TON; script uses fake-ton-config. |
| BUILD_DIR | No | `cmake-build-default-tdx` or env | Where the client binary is built. On GCP VM: only if you use a custom build dir. |
| COCOON_RUN_DIR | No | Set by script (e.g. `/tmp/run`) | Used by config renderer; usually leave unset. |
| COCOON_SUBST | No | Set by script to `build_dir/tee/cocoon-subst` | Only set if you run the render script manually. |

Summary for **fake-TON**: you must set **OWNER_ADDRESS** (any test address is fine). Everything else can use defaults.

### Real TON (production, mainnet)

| Variable | Obligatory? | Default / note | Where to set (GCP) |
|----------|-------------|----------------|--------------------|
| **OWNER_ADDRESS** | **Yes** | None | Your TON wallet address. Set in config file, CLI, or env (see above). |
| **NODE_WALLET_KEY** | **Yes** | None | Client wallet private key (base64). **Secret.** Set in env or config; on Cloud Run use Secret Manager or “Variables and secrets”. |
| **TON config file** | **Yes** | None | Path to `mainnet-full-ton-config.json` (or your TON config). Script needs `ton_config` / `ton_config_base` (paths), not an env var name; pass via config file or `--ton-config`. |
| ROOT_CONTRACT_ADDRESS | No | Script default | Override if your deployment uses a different root contract. |
| CLIENT_HTTP_PORT | No | 10000 | Set if you need another port (e.g. Cloud Run `PORT`). |
| BUILD_DIR / COCOON_RUN_DIR / COCOON_SUBST | No | As above | Same as fake-TON. |

Summary for **real TON**: **OWNER_ADDRESS**, **NODE_WALLET_KEY**, and a **TON config file** (via script config/CLI) are obligatory. The rest are optional.

### Where to set them on GCP

- **Compute Engine VM**  
  - **Option 1:** Export in shell before starting the client:  
    `export OWNER_ADDRESS=UQ...` then run `cocoon-launch` or your start script.  
  - **Option 2:** Config file (e.g. `client.conf`) with `[node]` section and `owner_address = ...`, `node_wallet_key = ...`, and pass that config to `cocoon-launch`.  
  - **Option 3:** systemd service file: `Environment=OWNER_ADDRESS=...` (use a secrets manager or restricted file for `NODE_WALLET_KEY` in production).

- **Cloud Run**  
  - **Console:** Service → Edit → Variables and secrets → Add variable (e.g. `OWNER_ADDRESS`, `CLIENT_HTTP_PORT`). For secrets (e.g. `NODE_WALLET_KEY`), use “Reference a secret” and create the secret in Secret Manager first.  
  - **gcloud:**  
    `gcloud run services update cocoon-client --set-env-vars="OWNER_ADDRESS=UQ...,CLIENT_HTTP_PORT=8080"`  
    For secrets: `--set-secrets="NODE_WALLET_KEY=my-wallet-key:latest"`.

- **Config file (any deployment)**  
  - If you use `cocoon-launch scripts/client.conf`, put in `client.conf`:  
    `[node]`  
    `type = client`  
    `owner_address = UQ...`  
    `node_wallet_key = ...` (or omit for fake-TON to use default).  
  - Paths like `ton_config` and `build_dir` go in the same `[node]` section or as CLI flags.

### Commands to set envs on the server

Run these **on the GCP VM** (or in your container entrypoint) **before** starting the Cocoon client. Replace placeholders with your real values.

**Fake-TON (testing) — minimum required**

```bash
# Obligatory: owner address (use any test address if you don't have one)
export OWNER_ADDRESS="UQAuz15H1ZHrZ_psVrAra7HealMIVeFq0wguqlmFno1f3B-m"

# Optional: only if you want a different HTTP port (default 10000)
# export CLIENT_HTTP_PORT=10000

# Optional: custom build dir (if you built elsewhere)
# export BUILD_DIR=/path/to/cocoon/build
```

**Real TON (production) — full set**

```bash
# Obligatory
export OWNER_ADDRESS="UQYourRealTonWalletAddress..."
export NODE_WALLET_KEY="your_base64_private_key_here"

# Optional: only if different from defaults
# export ROOT_CONTRACT_ADDRESS="EQBcXvP9DUA4k5tqUapcilt4kZnBzF0Ts7OW0Yp5FI0aN7g0"
# export CLIENT_HTTP_PORT=10000
# export BUILD_DIR=/path/to/cocoon/build
```

**Persist for later logins (optional)**

```bash
# Append to your shell profile so envs are set on every SSH login
echo 'export OWNER_ADDRESS="UQYourAddress..."' >> ~/.bashrc
# For real TON (avoid logging the key; use a separate secret file in production)
echo 'export NODE_WALLET_KEY="your_base64_key"' >> ~/.bashrc
source ~/.bashrc
```

**Or use a config file instead of env vars**

```bash
# Create client.conf for cocoon-launch (e.g. in cocoon repo)
cat > /path/to/cocoon/scripts/client.conf << 'EOF'
[node]
type = client
owner_address = UQYourAddress...
node_wallet_key = your_base64_key
fake_ton = false
ton_config = /path/to/cocoon/spec/mainnet-full-ton-config.json
ton_config_base = /path/to/cocoon/spec/mainnet-base-ton-config.json
build_dir = /path/to/cocoon/build
EOF

# Then run: ./scripts/cocoon-launch scripts/client.conf
```

For **fake-TON** with a config file, use `fake_ton = true` and you can omit `node_wallet_key` and TON config paths.

---

## Option A: Compute Engine VM

### 1. Create a VM

```bash
# Set your project and region (use GC_HS_PROJECT_ID, see README ENVS)
export GC_HS_PROJECT_ID=hyperlinksspacebot
export ZONE=us-central1-a

gcloud compute instances create cocoon-client \
  --project=$GC_HS_PROJECT_ID \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=20GB \
  --tags=cocoon-client
```

### 2. Allow HTTP (and optionally HTTPS) traffic

```bash
# Allow HTTP for the client (port 10000) or use a load balancer later
gcloud compute firewall-rules create allow-cocoon-client \
  --project=$GC_HS_PROJECT_ID \
  --allow=tcp:10000 \
  --target-tags=cocoon-client \
  --source-ranges=0.0.0.0/0
```

### 3. SSH into the VM and install dependencies

```bash
gcloud compute ssh cocoon-client --project=$GC_HS_PROJECT_ID
```

On the VM:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  cmake \
  ninja-build \
  git \
  python3 \
  libssl-dev \
  libz-dev \
  libjemalloc-dev \
  libsodium-dev \
  liblz4-dev \
  pkg-config
```

### 4. Clone Cocoon (origin branch, no local changes)

Use the **origin** branch of the Cocoon repo (upstream or your fork’s origin branch):

```bash
# Clone (use your fork or upstream)
git clone --recursive https://github.com/HyperlinksSpace/cocoon.git
cd cocoon

# Use origin branch only (no local patches)
git fetch origin
git checkout origin
git submodule update --init --recursive
```

If you use the official repo:

```bash
git clone --recursive https://github.com/TelegramMessenger/cocoon.git
cd cocoon
# Then checkout the branch that provides the client (e.g. main or the one documented in their repo)
```

### 5. Build

```bash
mkdir -p build && cd build
cmake -GNinja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_SHARED_LIBS=OFF \
  -DTON_USE_JEMALLOC=ON \
  -DTON_USE_ABSEIL=OFF \
  -DTON_ONLY_TONLIB=ON \
  -DTON_USE_ROCKSDB=ON \
  ..
cmake --build . -j$(nproc) --target cocoon-all
```

Or use the launch script to build (from repo root):

```bash
cd /path/to/cocoon
./scripts/cocoon-launch --build-dir "$(pwd)/build" --just-build
```

Ensure these exist after build:

- `build/client-runner`
- `build/tee/router`
- `build/tee/cocoon-subst`

### 6. Prepare config (client spec)

From the Cocoon repo root, using the **client** spec and config:

**Test / fake-TON (no real TON):**

```bash
# Render configs for client (script may differ on origin branch; adjust paths if needed)
export COCOON_RUN_DIR=/tmp/run
mkdir -p $COCOON_RUN_DIR

# If cocoon-launch supports --type client --fake-ton:
./scripts/cocoon-launch --type client --test --fake-ton
# Follow any prompts; it will render config under a temp dir or $COCOON_RUN_DIR.
```

**Production (real TON):**

- Place `spec/mainnet-full-ton-config.json` (or your TON config) in the repo.
- Set `OWNER_ADDRESS` and `NODE_WALLET_KEY` (and optionally `ROOT_CONTRACT_ADDRESS`).
- Run with config file, e.g. `./scripts/cocoon-launch scripts/client.conf` (see official Cocoon docs for exact config format).

If the origin branch uses a **config file** (e.g. `scripts/client.conf`), use that and set env vars as required by the script.

### 7. Run router + client

**Using cocoon-launch (if it supports client-only on Linux):**

```bash
./scripts/cocoon-launch --type client --test --fake-ton
# Or for production:
# ./scripts/cocoon-launch scripts/client.conf
```

**Manual run (if you have rendered configs):**

```bash
# Terminal 1: router (SOCKS5 for client’s outbound connections)
./build/tee/router -S 8116@any --serialize-info

# Terminal 2: client (OpenAI-compatible API on port 10000)
./build/client-runner --config /tmp/run/client-config.json -v3 --disable-ton /tmp/run/fake-ton-config.json
```

For production, omit `--disable-ton` and pass the real TON config path.

### 8. Open port 10000 and test

From your machine:

```bash
export VM_IP=$(gcloud compute instances describe cocoon-client --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
curl -s "http://$VM_IP:10000/v1/models" | head -20
```

Use this URL as `COCOON_CLIENT_URL` in your AI backend (e.g. `http://$VM_IP:10000`). For production, put the client behind HTTPS (see below).

---

## Option B: Cloud Run (container)

Run Cocoon client (and router) in a container and deploy to Cloud Run for HTTPS and scaling.

### 1. Dockerfile (in your repo or a separate cocoon-deploy repo)

Create a directory (e.g. `cocoon-gcp`) with:

**Dockerfile:**

```dockerfile
# Build stage
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y \
  build-essential cmake ninja-build git python3 \
  libssl-dev libz-dev libjemalloc-dev libsodium-dev liblz4-dev pkg-config

WORKDIR /src
RUN git clone https://github.com/HyperlinksSpace/cocoon.git . \
  && git fetch origin && git checkout origin \
  && git submodule update --init --recursive

WORKDIR /src/build
RUN cmake -GNinja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_SHARED_LIBS=OFF \
  -DTON_USE_JEMALLOC=ON \
  -DTON_USE_ABSEIL=OFF \
  -DTON_ONLY_TONLIB=ON \
  -DTON_USE_ROCKSDB=ON \
  .. \
  && cmake --build . -j$(nproc) --target cocoon-all

# Run stage
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y libssl3 zlib1g libjemalloc2 libsodium23 liblz4-1 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/build/client-runner /app/
COPY --from=builder /src/build/tee/router /app/
COPY --from=builder /src/build/tee/cocoon-subst /app/

# Pre-render client config (simplified; for fake-TON you may bake a minimal config)
# For production, mount config or generate at startup via entrypoint.
ENV PORT=8080
EXPOSE 8080

# Cloud Run expects one process. Run router in background, then client.
# Client must listen on $PORT for Cloud Run.
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
```

**entrypoint.sh:**

```bash
#!/bin/bash
set -e
# Start router in background (client uses it for RA-TLS to proxies)
/app/router -S 8116@any --serialize-info &
# Start client; Cloud Run sends traffic to PORT
# If client-runner doesn’t read PORT, use a reverse proxy (e.g. nginx) that listens on $PORT and proxies to 10000
exec /app/client-runner --config /app/client-config.json -v3 --disable-ton /app/fake-ton-config.json
```

You must provide `client-config.json` and `fake-ton-config.json` (or real TON config) in the image or via a volume. If the origin client only listens on 10000, run a small reverse proxy (e.g. nginx or `socat TCP-LISTEN:$PORT,fork TCP:127.0.0.1:10000`) so Cloud Run can send traffic to `$PORT`.

### 2. Build and push image

```bash
export GC_HS_PROJECT_ID=hyperlinksspacebot
gcloud builds submit --tag gcr.io/$GC_HS_PROJECT_ID/cocoon-client .
```

### 3. Deploy to Cloud Run

```bash
gcloud run deploy cocoon-client \
  --image gcr.io/$GC_HS_PROJECT_ID/cocoon-client \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --port 8080
```

Use the reported URL as `COCOON_CLIENT_URL` (e.g. `https://cocoon-client-xxx.run.app`).

---

## HTTPS and production

- **Compute Engine:** Put an HTTP(S) load balancer in front of the VM, or run nginx on the VM as an HTTPS reverse proxy to `127.0.0.1:10000`.
- **Cloud Run:** Uses HTTPS by default; use the Cloud Run URL as `COCOON_CLIENT_URL`.
- Restrict firewall rules to your AI backend’s IPs or VPC where possible.
- For production, use **real TON**: set `OWNER_ADDRESS`, `NODE_WALLET_KEY`, and a proper TON config; do not use `--disable-ton` / fake-TON.

---

## Connect your app

In your **AI backend** (e.g. HyperlinksSpaceBot `ai/backend`):

- Set `LLM_PROVIDER=cocoon`.
- Set `COCOON_CLIENT_URL` to your GCP endpoint:
  - VM: `http://<VM_EXTERNAL_IP>:10000`
  - Cloud Run: `https://cocoon-client-xxx.run.app`
- Optional: `COCOON_MODEL` if your client uses a specific model name.

Your app sends requests to the AI backend; the backend calls Cocoon at `COCOON_CLIENT_URL` for generations.

---

## Troubleshooting

| Issue | What to check |
|-------|----------------|
| **Quota 'GPUS_PER_GPU_FAMILY' exceeded. Limit: 0.0 … NVIDIA_H100** | Your project has no H100 GPU quota. Go to [Quotas](https://console.cloud.google.com/iam-admin/quotas), switch to **All quotas**, search for `GPUS_PER_GPU_FAMILY` or `NVIDIA_H100`, select the row for region **us-central1** (or your target region), click **Edit quotas** / pencil, request at least **1**, submit. For Spot A3 VMs you may also need **PREEMPTIBLE_NVIDIA_H100_GPUS**. Wait for approval (often 24–48 h). |
| **Quota request denied** (“unable to grant at this time” / new project) | If the project or billing is new: wait **48 hours** and resubmit the same request, or use the project for a few days to build billing history. To escalate: contact [Google Cloud Sales](https://cloud.google.com/contact/) or your Sales Rep and ask for H100 GPU quota for confidential AI workload (Cocoon); they can sometimes help with quota. Meanwhile run **client + router only** (e2-medium or T4 VM) without the worker. |
| First SSH: "no SSH key for gcloud" / "Store key in cache?" | Normal on first use. gcloud generates keys and uploads the public key to the project. At "Store key in cache? (y/n)" type **y** and Enter to trust the VM and connect. |
| Build fails (missing libs) | Install dev packages: `libssl-dev`, `libz-dev`, `libjemalloc-dev`, `libsodium-dev`, `liblz4-dev`, `pkg-config`. |
| Client won’t start | Ensure config files exist (`client-config.json`, TON or fake-ton config). Run from repo root or set paths in the command. |
| Connection refused from app | Firewall: allow `tcp:10000` (VM) or use Cloud Run URL. Ensure client-runner is bound to `0.0.0.0` (not only 127.0.0.1). |
| Origin branch has no `--type client` | Use the run mode documented in that branch (e.g. config file `scripts/client.conf` and required env vars). |

---

## Summary

- Use **origin** Cocoon only (no local changes): clone, `git checkout origin`, build on Linux.
- **GCP:** Run **client + router** on a Compute Engine VM or in a container on Cloud Run.
- Expose the client over HTTP (VM) or HTTPS (Cloud Run or load balancer).
- Set your AI backend’s `COCOON_CLIENT_URL` to this endpoint to use Cocoon for generations on Google Cloud.

For full deployment and testing (including TDX, proxy, worker), see the official [Cocoon deployment guide](https://github.com/TelegramMessenger/cocoon) (Use Cases 2–4); this document focuses on **client-only on GCP** without TDX.
