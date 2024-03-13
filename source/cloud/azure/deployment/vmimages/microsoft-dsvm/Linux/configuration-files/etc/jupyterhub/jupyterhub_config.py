from oauthenticator.azuread import LocalAzureAdOAuthenticator
from jupyter_client.localinterfaces import public_ips
from tornado import gen
from jupyterhub.auth import LocalAuthenticator
import re
import os
import json
import shlex
import subprocess
import pwd
c.Application.log_level = 'DEBUG'
c.Spawner.args = ['--NotebookApp.allow_origin=*','--config=/etc/jupyterhub/jupyter_config.py']
c.Spawner.http_timeout = 300
c.Spawner.start_timeout = 300

class NormalizedUsernameLocalAzureAdOAuthenticator(LocalAzureAdOAuthenticator):
    def add_user_to_group(self,user):
        group='vmusers'
        print("Adding '%s' to '%s'..." % (user,group))

        cmd = "sudo usermod -a -G %s %s" % (group, user)

        ret = os.system(cmd)

        if ret != 0:
            print("Failed!")
            return False
        
        return True


    def create_blobfuse_symlink(self,user):
        home_uname = user

        print("Creating blobfuse symlink for '%s'..." % user)

        cmd = "sudo ln -s /data/blobfuse /home/%s/notebooks/data" % home_uname

        ret = os.system(cmd)

        if ret != 0:
            print("Failed!")
            return False

        cmd = "sudo ln -s /data/blobfuse /home/%s/data" % home_uname

        ret = os.system(cmd)

        if ret != 0:
            print("Failed!")
            return False
        
        return True
    def normalize_username(self, username):
        return re.sub('(\s|\(|\)|,|\.)', '', username.lower()[0:32])

    def add_user(self, user):
        self.log.info('creating local users...')
        if user.name in [entry.pw_name for entry in pwd.getpwall()]:
            self.log.info('user {} is already created.'.format(user.name))
        else:
            subprocess.run(['sudo', 'adduser', '-q', '-gecos',
                            '""', '--disabled-password', '{}'.format(user.name)])
            self.add_user_to_group(user.name)
            self.create_blobfuse_symlink(user.name)
        self.log.info('finished creating local user {}'.format(user.name))
        if self.allowed_users:
            self.log.info('add user {} to allow list'.format(user.name))
            self.allowed_users.add(user.name)


c.Spawner.default_url = '/lab'

# The command used for starting notebooks.
c.Spawner.cmd = ['/anaconda/bin/jupyterhub-singleuser']

c.Spawner.notebook_dir = '~/notebooks'

os.environ['CONDA_EXE']='/anaconda/bin/conda'
os.environ['JULIA_DEPOT_PATH']='/opt/julia/latest/packages/'

c.Spawner.env_keep = ['JULIA_DEPOT_PATH', 'CONDA_EXE']

ip = public_ips()[0]

c.JupyterHub.ip = '0.0.0.0'
c.JupyterHub.port = 8000
c.JupyterHub.hub_ip = ip

c.JupyterHub.authenticator_class = NormalizedUsernameLocalAzureAdOAuthenticator

c.Authenticator.allowed_users = allowed_users = set()

allowed_users.add("{initialJHubUserName}")

c.Authenticator.admin_users = admin = set()

admin.add("{initialJHubUserName}")

c.Authenticator.delete_invalid_users = True

c.AzureAdOAuthenticator.tenant_id = os.environ.get('AAD_TENANT_ID')
c.AzureAdOAuthenticator.oauth_callback_url = 'https://{vm_fqdn}:8000/hub/oauth_callback'
c.AzureAdOAuthenticator.client_id = '{client_id}'
c.AzureAdOAuthenticator.client_secret = '{client_secret}'

# Path to SSL key file for the public facing interface of the proxy
c.JupyterHub.ssl_key = '/etc/letsencrypt/live/{vm_fqdn}/privkey.pem'
c.JupyterHub.ssl_cert = '/etc/letsencrypt/live/{vm_fqdn}/fullchain.pem'