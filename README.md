Production wrapper for Pilot 3

The container image contains the pilot wrapper and pilot tarball, enabling execution of the pilot in CVMFS-free environments. 
The argument strings given to the container are passed to the pilot wrapper. Make sure you have a token (and rucio.cfg for Rucio access) in your current directory and mount it to /scratch inside the container.
Here's an example of running the container without CVMFS:

```bash
$ echo -n <your_token> > token.txt
$ cp /somewhere/rucio.cfg .
$ docker run -v ${PWD}:/scratch -e OIDC_AUTH_TOKEN=/scratch/token.txt -e OIDC_AUTH_ORIGIN=<vo.role> -it --platform linux/amd64 ghcr.io/pandawms/pilot-wrapper:master -s <site_name> -r <queue_name> -q <queue_name> -j unified -i PR --pythonversion 3 -w generic --pilot-user rubin --url <panda_server_url> -d --localpy --piloturl local --container -t
```
where you need to replace `<blah>`. E.g.:
```bash
$ # x509 for rucio access
$ cp ~/.globus/user* .
$ cp /tmp/x509up_u123456 .
$ # rucio config with x509
$ cat rucio.cfg
[client]
rucio_host = https://voatlasrucio-server-prod.cern.ch:443
auth_host = https://atlas-rucio-auth.cern.ch:443
client_cert = /scratch/usercert.pem
client_key = /scratch/userkey.pem
client_x509_proxy = /scratch/x509up_u123456
auth_type = x509_proxy
request_retries = 3
$ docker run -v ${PWD}:/scratch -e OIDC_AUTH_TOKEN=/scratch/token.txt -e OIDC_AUTH_ORIGIN=panda_dev.pilot -it --platform linux/amd64 ghcr.io/pandawms/pilot-wrapper:master -s CERN -r CERN -q CERN -j unified -i PR --pythonversion 3 -w generic --pilot-user rubin --url https://aipanda123.cern.ch:25443 -d --localpy --piloturl local --container -t
```
