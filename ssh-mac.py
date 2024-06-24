import argparse
import logging
from contextlib import ExitStack
from pathlib import Path
from time import sleep

from paramiko import MissingHostKeyPolicy, SSHClient
from paramiko.ssh_exception import SSHException
from paramiko_tunnel.tunnel import Tunnel
from remoteit_ssh_client import main

from interactive_shell import open_shell

logging.basicConfig()


def parse_arguments():
    parser = argparse.ArgumentParser(description="SSH Argument Parser")
    parser.add_argument("-J", dest="jump_host")
    parser.add_argument("-N")
    parser.add_argument(
        "-L", dest="tunnels", action="append", metavar="port:host:hostport"
    )
    parser.add_argument("-v", dest="verbose", action="store_true")
    parser.add_argument("host")

    args = parser.parse_args()
    print(args)

    if args.verbose:
        logging.getLogger("paramiko").setLevel(logging.DEBUG)
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
                key_filename=str(Path("~/.ssh/id_ed25519").expanduser()),
            )
        except SSHException as error:
            logging.exception("ssh exception")
        else:
            return client


def execute_tunnel(args):
    with ExitStack() as stack:
        for tunnel_arg in args.tunnels:
            *local, remote_host, remote_port = tunnel_arg.split(":")
            kwargs = {}
            if len(local) == 1:
                kwargs["bind_address_and_port"] = ("", int(local[0]))
            elif len(local) == 2:
                kwargs["bind_address_and_port"] = (local[0], int(local[1]))

            tunnel = stack.enter_context(
                Tunnel(
                    paramiko_session=client,
                    remote_host="localhost",
                    remote_port=int(remote_port),
                    **kwargs,
                ),
            )
            print(tunnel)
        while True:
            sleep(1)


if __name__ == "__main__":
    args = parse_arguments()
    client = init_instance()
    if args.tunnels:
        execute_tunnel(args)
    else:
        open_shell(client)
