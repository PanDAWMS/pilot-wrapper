Production wrapper for Pilot 3

To run the container:

```bash
$ echo -n <your_token> > token.txt
$ docker run -v ${PWD}:/scratch -e OIDC_AUTH_TOKEN=/scratch/token.txt -e OIDC_AUTH_ORIGIN=<vo.role> -it pilot -s CERN -r CERN -q CERN -j unified -i PR --pythonversion 3 -w generic --pilot-user rubin --url https://aipanda123.cern.ch -d --localpy --piloturl local --container -t
```

