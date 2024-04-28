import logging
from pathlib import Path
from time import sleep
import argparse

from paramiko import MissingHostKeyPolicy, SSHClient
from paramiko.ssh_exception import SSHException
from remoteit_ssh_client import main

from interactive_shell import open_shell
from paramiko_tunnel.tunnel import Tunnel

logging.basicConfig()
# logging.getLogger("paramiko").setLevel(logging.DEBUG)


def parse_arguments():
    parser = argparse.ArgumentParser(description="SSH Argument Parser")
    parser.add_argument("-J", dest='jump_host')
    parser.add_argument("-L", dest='tunnel', nargs='+', metavar="port:host:hostport")
    parser.add_argument("host")

    args = parser.parse_args()
    print(args)
    return args

def init_instance():
    client = SSHClient()
    client.set_missing_host_key_policy(MissingHostKeyPolicy())
    connection_params = main()
    print(connection_params)

    for i in range(3):
        try:
            client.connect(
                *connection_params.values(),
                timeout=1,
                username="hwangsehyun",
                key_filename=str(Path("~/.ssh/id_ed25519").expanduser())
            )
            return client
        except SSHException:
            logging.exception("ssh exception")


if __name__ == "__main__":
    parse_arguments()
    #asdf
    client = init_instance()
    with Tunnel(
        paramiko_session=client,
        remote_host='localhost',
        remote_port=8889,
    ) as tunnel:
        print(f'{tunnel.bind_address=} {tunnel.bind_port=}')
        while True:
            sleep(1)
    open_shell(client)
