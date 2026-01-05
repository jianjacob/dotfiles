# Useful commands

- [Useful commands](#useful-commands)
  - [Ubuntu](#ubuntu)
    - [Check who's trying to connect to ssh](#check-whos-trying-to-connect-to-ssh)
    - [Unban self from fail2ban](#unban-self-from-fail2ban)
  - [Github](#github)
    - [Signing](#signing)
      - [Confirm commit are signed](#confirm-commit-are-signed)
      - [Tell git to sign commits](#tell-git-to-sign-commits)


## Ubuntu

### Check who's trying to connect to ssh
`sudo grep "Failed" /var/log/auth.log | tail -20`


> [!NOTE]
> Block access to port 22, or disable root login

### Unban self from fail2ban
`sudo fail2ban-client set sshd unbanip YOUR_IP`


## Github

### Signing

#### Confirm commit are signed
`git log --show-signature -1`

#### Tell git to sign commits
```bash
git config --global gpg.format ssh
git config --global user.signingkey <path-to-private-key>
git config --global commit.gpgsign true
```
> [!NOTE]
> replace with path to private ssh key (eg: windows -> ~/.ssh/id_ed25519)

```bash
# verify 
git config --global --get gpg.format
git config --global --get user.signingkey
```