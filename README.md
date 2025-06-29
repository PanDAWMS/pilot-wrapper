Production wrapper for Pilot 3

To run the container:

```bash
$ echo -n <your_token> > token.txt
$ cp /somewhere/rucio.cfg .
$ docker run -v ${PWD}:/scratch -e OIDC_AUTH_TOKEN=/scratch/token.txt -e OIDC_AUTH_ORIGIN=<vo.role> -it --platform linux/x86_64 ghcr.io/pilot-wrapper/pilot-wrapper:master -s <site_name> -r <queue_name> -q <queue_name> -j unified -i PR --pythonversion 3 -w generic --pilot-user rubin --url <panda_server_url> -d --localpy --piloturl local --container -t
```
where you need to replace `<blah>`. E.g.:
```bash
$ docker run -v ${PWD}:/scratch -e OIDC_AUTH_TOKEN=/scratch/token.txt -e OIDC_AUTH_ORIGIN=panda_dev.pilot -it --platform linux/x86_64 ghcr.io/pilot-wrapper/pilot-wrapper:master -s CERN -r CERN -q CERN -j unified -i PR --pythonversion 3 -w generic --pilot-user rubin --url https://aipanda123.cern.ch:25443 -d --localpy --piloturl local --container -t
```
