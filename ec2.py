#!/usr/bin/env python3

from pprint import pprint
from os import environ
import termios
import sys
import tty
from fcntl import ioctl
from struct import unpack
from select import select
from paramiko.py3compat import u
from socket import timeout
import curses

import boto3
from simple_term_menu import TerminalMenu
from paramiko import SSHClient
from interactive_shell import open_shell

ec2 = boto3.client('ec2')


def get_efs():
    efs = None
    with open('/etc/fstab') as file:
        for line in file:
            lst = line.split()
            if 'efs' in lst:
                efs = lst[0]

    assert efs, 'Can not detect EFS id in /etc/fstab'
    efs = efs.split(':')[0]
    print(efs)
    return efs


USER = {
    "AmazonLinux2": 'ec2-user',
    "Amazon Linux": 'ec2-user',
    "NVIDIA": 'ec2-user',
    "Debian": 'admin',
    "Ubuntu": 'ubuntu',
    "CentOS": 'centos',
}


def choose_instance():
    instances = sum([
        x['Instances']
        for x in ec2.describe_instances(Filters=[{
            'Name': 'instance-state-name',
            'Values': ('running', )
        }])['Reservations']
    ], [])
    # pprint(instances)

    images = describe_images([instance['ImageId'] for instance in instances])
    print(images)
    descriptions = [([': '.join(x.values()) for x in instance.get('Tags', {})],
                     instance['InstanceType'], images[instance['ImageId']])
                    for instance in instances]
    index = TerminalMenu(map(str, descriptions)).show()
    instance = instances[index]
    image = images[instance['ImageId']]

    user = next((value for key, value in USER.items() if key in image), None)
    ip = instance['PrivateIpAddress']
    print(f'Connecting to {user}@{ip}')

    client = SSHClient()
    client.load_system_host_keys()
    client.connect(ip,
                   username=user,
                   key_filename=f'{environ["HOME"]}/.ssh/Default.pem')
    stdout = client.exec_command('ls /mnt')[1].read()

    if (len(stdout)):
        print(stdout)
    else:
        print('Mounting EFS')
        stdout, stderr = client.exec_command(
            f'sudo mount -t efs {get_efs()} /mnt')[1:]
        stdout, stderr = stdout.read(), stderr.read()
        assert not stdout
        assert not stderr
        print('EFS mounted')

    open_shell(client)


def describe_images(id):
    return {
        x['ImageId']: x['Description']
        for x in ec2.describe_images(ImageIds=id)['Images']
    }


choose_instance()
#print(describe_images(['ami-0b6d6d4ad3367c8f0', 'ami-0b6d6d4ad3367c8f0']))
