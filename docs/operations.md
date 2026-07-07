# Operations

## Validate this repo

```bash
make validate
make test
```

`make validate` checks required files, shell syntax, Python syntax, example YAML, and pillar rendering.

## Bootstrap a minion

Run on the target Ubuntu host:

```bash
sudo ./scripts/bootstrap-minion.sh \
  --master salt.example.internal \
  --id example-vllm-node \
  --roles base,docker,nvidia,llm_vllm
```

Useful options:

| Option | Purpose |
| --- | --- |
| `--install-method apt` | Install `salt-minion` from configured apt repos. Default. |
| `--install-method bootstrap` | Use `https://bootstrap.saltproject.io` when apt repos are not already configured. |
| `--install-method none` | Only write config/grains and restart if installed. |
| `--master-finger <fingerprint>` | Pin the Salt master public key fingerprint. |
| `--no-start` | Write files but do not enable/restart `salt-minion`. |

The script writes:

- `/etc/salt/minion.d/99-redsalt.conf`
- `/etc/salt/grains`

## Master-side registration

On the Salt master:

```bash
salt-key -L
salt-key -a 'example-vllm-node'
```

Add a pillar file to the master repo:

```bash
./scripts/render-pillar.py \
  --minion-id example-vllm-node \
  --roles base,docker,nvidia,llm_vllm \
  --output ../redsalt-master/pillar/minions/example-vllm-node.sls
```

Then add the matching entry to `redsalt-master/pillar/top.sls`:

```yaml
base:
  'example-vllm-node':
    - minions.example-vllm-node
```

Commit and deploy the master repo, then restart or refresh master-side Salt services as needed.

## Verification from the Salt master

```bash
salt 'example-vllm-node' test.ping
salt 'example-vllm-node' grains.get redsalt
salt 'example-vllm-node' pillar.get roles
salt 'example-vllm-node' state.show_highstate
salt 'example-vllm-node' state.apply test=True
```

After apply, verify baseline SSH access state:

```bash
salt 'example-vllm-node' user.info darthai
salt 'example-vllm-node' file.file_exists /home/darthai/.ssh/authorized_keys
```

For vLLM nodes, verify service health:

```bash
salt 'example-vllm-node' service.status vllm-openai
salt 'example-vllm-node' cmd.run 'docker compose -f /opt/redsalt/vllm/docker-compose.yml ps'
salt 'example-vllm-node' cmd.run 'curl -fsS http://127.0.0.1:8000/v1/models'
```

## Troubleshooting

- If `salt-key -L` does not show the minion, confirm outbound TCP/4505 and TCP/4506 connectivity from minion to master.
- If `test.ping` fails after key acceptance, restart the minion: `systemctl restart salt-minion`.
- If roles are missing from `pillar.get roles`, update `redsalt-master/pillar/top.sls` and the minion pillar file; grains alone are not sufficient.
- If highstate attempts the wrong services, inspect the master-side pillar booleans first.
