#!/usr/bin/env python
from pathlib import Path

from paramiko import SSHClient, MissingHostKeyPolicy
from remoteit_ssh_client import main
from interactive_shell import open_shell

def init_instance():
    client = SSHClient()
    client.set_missing_host_key_policy(MissingHostKeyPolicy())
    connection_params = main()

    print(connection_params)
    client.connect(*connection_params.values(),
                   username="hwangsehyun",
                   key_filename=str(Path("~/.ssh/id_ed25519").expanduser()))
    return client

if __name__ == "__main__":
    client = init_instance()
    open_shell(client)
