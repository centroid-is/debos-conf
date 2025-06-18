# Using ansible

On local machine
```bash
scp ansible-playbook.yml centroid@10.11.11.191:~/
```

On remote machine
```bash
su
apt-get install ansible
export PATH="$PATH:/usr/sbin" # for sysctl
ansible-playbook -i localhost -e 'root_password=foo' -e 'centroid_password=bar' ansible-playbook.yml
```

