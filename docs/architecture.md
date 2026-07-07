# Architecture

## Relationship to redsalt-master

`redsalt-master` owns desired state and pillar policy. `redsalt-minion` prepares hosts to connect to that master and provides repeatable helper scripts for generating the required master-side pillar.

```text
Ubuntu host
  ├─ salt-minion package/service
  ├─ /etc/salt/minion.d/99-redsalt.conf   # master/id/environment
  └─ /etc/salt/grains                     # non-authoritative inventory metadata

Salt master
  ├─ redsalt-master/states                # role states
  └─ redsalt-master/pillar                # authoritative role assignment/config
```

## Configuration contract

The minion configuration sets:

- `master`: DNS name or IP address of the Salt master.
- `id`: stable minion ID used by `pillar/top.sls` and `salt-key`.
- `saltenv` / `pillarenv`: `base`, matching the current master roots.
- optional `master_finger`: Salt master public key pinning after verification.

## Role contract

`redsalt-master/states/top.sls` matches pillar booleans such as:

```yaml
roles:
  base: true
  docker: true
  nvidia: true
  llm_vllm: true
```

`configs/grains.example` and `bootstrap-minion.sh --roles` write the same role names into grains for inventory visibility, but grains do not authorize or select highstate in the master repo.

## vLLM node flow

For a GPU vLLM node, use roles:

```text
base,docker,nvidia,llm_vllm
```

Then generate a pillar file with `scripts/render-pillar.py`; it includes the same Docker, NVIDIA, model, and vLLM defaults used by the master example minion.
