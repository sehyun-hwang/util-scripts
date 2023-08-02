#!/usr/bin/env python

from os import environ

import boto3
from simple_term_menu import TerminalMenu
from paramiko import SSHClient
from interactive_shell import open_shell

ec2 = boto3.client('ec2')


USER = {
    "AmazonLinux2": 'ec2-user',
    "Amazon Linux": 'ec2-user',
    "NVIDIA": 'ubuntu',
    "Debian": 'admin',
    "Ubuntu": 'ubuntu',
    "CentOS-Stream": 'ec2-user',
    "CentOS": 'centos',
}


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
    if not index:
        return
    instance = instances[index]
    image = images[instance['ImageId']]

    user = next(value for key, value in USER.items() if key in image)
    ip = instance['PrivateIpAddress']
    print(f'Connecting to {user}@{ip}')
    return user, ip


def init_instance(user, ip):
    client = SSHClient()
    client.load_system_host_keys()
    client.connect(ip,
                   username=user,
                   key_filename=f'{environ["HOME"]}/.ssh/Default.pem')
    stdout = client.exec_command('ls /mnt')[1].read()

    if len(stdout):
        print(stdout)
    else:
        print('Mounting EFS')
        stdout, stderr = client.exec_command(
            f'sudo mount -t efs {get_efs()} /mnt')[1:]
        stdout, stderr = stdout.read(), stderr.read()

        if stdout or stderr:
            print('EFS mount failed')
            print(stdout, stderr)
        else:
            print('EFS mounted')
    return client


def describe_images(image_ids):
    return {
        x['ImageId']: x['Description']
        for x in ec2.describe_images(ImageIds=image_ids)['Images']
    }


if __name__ == '__main__':
    #print(describe_images(['ami-0b6d6d4ad3367c8f0', 'ami-0b6d6d4ad3367c8f0']))
    instance = choose_instance()
    client = init_instance(*instance)
    open_shell(client)
