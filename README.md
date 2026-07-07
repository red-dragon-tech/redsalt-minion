# redsalt-minion

Bootstrap and configuration helpers for Salt minions that join the `red-dragon-tech/redsalt-master` Salt environment.

This repository is the minion-side companion to `redsalt-master`. It focuses on safely preparing Ubuntu hosts to connect to the Salt master, request a key, and receive the role-driven highstate defined in the master repo.

## Scope

- **Target OS:** Ubuntu hosts that will run `salt-minion`
- **Salt master repo:** `red-dragon-tech/redsalt-master`
- **Master state/pillar model:** pillar-driven roles: `base`, `docker`, `nvidia`, `llm_vllm`
- **Minion config path:** `/etc/salt/minion.d/99-redsalt.conf`
- **Inventory grains path:** `/etc/salt/grains`
- **Secrets:** no private keys, tokens, or passwords are committed

## Repository layout

```text
.
├── configs/
│   ├── grains.example
│   └── minion.d/99-redsalt.conf.example
├── docs/
│   ├── architecture.md
│   ├── operations.md
│   └── security.md
├── scripts/
│   ├── bootstrap-minion.sh
│   ├── render-pillar.py
│   └── validate.py
└── tests/
    └── test_repo_static.py
```

## Quick start

Validate the repo locally:

```bash
make validate
make test
```

Bootstrap a new minion on the target host:

```bash
sudo ./scripts/bootstrap-minion.sh \
  --master salt.example.internal \
  --id example-vllm-node \
  --roles base,docker,nvidia,llm_vllm
```

Generate the matching pillar snippet for the Salt master repo:

```bash
./scripts/render-pillar.py \
  --minion-id example-vllm-node \
  --roles base,docker,nvidia,llm_vllm \
  --output /tmp/example-vllm-node.sls
```

Copy that output into the master checkout as:

```text
redsalt-master/pillar/minions/example-vllm-node.sls
```

Then add the minion to `redsalt-master/pillar/top.sls`:

```yaml
base:
  'example-vllm-node':
    - minions.example-vllm-node
```

## Role mapping

The master repo selects states with pillar booleans, not minion grains. This repo writes grains for operator inventory only; access and service policy must still be represented in master-side pillar.

Supported roles:

| Role | Purpose |
| --- | --- |
| `base` | Common packages, managed directories, and `darthai` SSH access from master pillar |
| `docker` | Docker Engine and Compose plugin |
| `nvidia` | NVIDIA Container Toolkit and optional driver package policy |
| `llm_vllm` | vLLM OpenAI-compatible service via Docker Compose |

## Minion lifecycle

1. Run `scripts/bootstrap-minion.sh` on the target host.
2. Confirm the minion key appears on the Salt master:
   ```bash
   salt-key -L
   ```
3. Accept the minion key on the master:
   ```bash
   salt-key -a '<minion-id>'
   ```
4. Add master-side pillar with `scripts/render-pillar.py` output.
5. Preview and apply highstate from the master:
   ```bash
   salt '<minion-id>' test.ping
   salt '<minion-id>' pillar.items
   salt '<minion-id>' state.apply test=True
   salt '<minion-id>' state.apply
   ```
