# Useful commands

## Table of Contents

- [Useful commands](#useful-commands)
- [Ubuntu](#ubuntu)
  - [Check who's trying to connect to ssh](#check-whos-trying-to-connect-to-ssh)



## Ubuntu

### Check who's trying to connect to ssh
`sudo grep "Failed" /var/log/auth.log | tail -20`

> [!NOTE]
> Block access to port 22, or disable root login