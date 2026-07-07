# Security

## Secrets boundary

This repository must not contain:

- SSH private keys
- Salt minion private keys from `/etc/salt/pki/minion/`
- password hashes
- API tokens
- registry credentials
- TLS private keys

The minion bootstrap script writes only non-secret configuration and inventory metadata. Salt minion keypairs are generated locally by Salt and must remain on the minion host.

## Master trust

Prefer pinning the Salt master public key fingerprint with `--master-finger` after verifying it through an out-of-band trusted channel.

Example:

```bash
sudo ./scripts/bootstrap-minion.sh \
  --master salt.example.internal \
  --id example-vllm-node \
  --master-finger 'aa:bb:cc:dd:...'
```

## Role assignment

Do not treat grains as an authorization boundary. Grains are minion-controlled and useful for inventory only. `redsalt-master` intentionally uses pillar role booleans for highstate selection.

## Key acceptance

Only accept minion keys on the Salt master after verifying the minion ID and fingerprint belong to the expected host:

```bash
salt-key -f '<minion-id>'
salt-key -a '<minion-id>'
```

## SSH access

`redsalt-master` manages the `darthai` SSH account via pillar and public authorized keys. Public keys may be committed as access policy; private keys must never be committed.
